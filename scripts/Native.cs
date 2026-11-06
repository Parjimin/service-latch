// Lab installer only. Uses documented Win32 APIs; never loaded by the Rust worker.
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class ServiceLatchPoc1ANative {
    [StructLayout(LayoutKind.Sequential)] struct SecurityAttributes {
        public int Length; public IntPtr Descriptor;
        [MarshalAs(UnmanagedType.Bool)] public bool InheritHandle;
    }
    [StructLayout(LayoutKind.Sequential)] struct PrivilegesInfo { public IntPtr Names; }
    [StructLayout(LayoutKind.Sequential)] struct Status {
        public uint Type, State, Accepted, Win32Exit, SpecificExit, Checkpoint, WaitHint;
    }
    [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern IntPtr OpenSCManagerW(string machine, string database, uint access);
    [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern IntPtr OpenServiceW(IntPtr scm, string name, uint access);
    [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern IntPtr CreateServiceW(IntPtr scm, string name, string display, uint access,
        uint type, uint start, uint error, string binary, string group, IntPtr tag,
        string dependencies, string account, string password);
    [DllImport("advapi32.dll", EntryPoint="ChangeServiceConfig2W", ExactSpelling=true, SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool SetPrivileges(IntPtr service, uint level, ref PrivilegesInfo info);
    [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool StartServiceW(IntPtr service, int count,
        [MarshalAs(UnmanagedType.LPArray, ArraySubType=UnmanagedType.LPWStr)] string[] args);
    [DllImport("advapi32.dll", SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool ControlService(IntPtr service, uint control, out Status status);
    [DllImport("advapi32.dll", SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool DeleteService(IntPtr service);
    [DllImport("advapi32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool CloseServiceHandle(IntPtr handle);
    [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool ConvertStringSecurityDescriptorToSecurityDescriptorW(string sddl,
        uint revision, out IntPtr descriptor, out uint size);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool CreateDirectoryW(string path, ref SecurityAttributes security);
    [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr memory);

    static IntPtr Manager(uint access) {
        IntPtr h=OpenSCManagerW(null,null,access);
        if(h==IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
        return h;
    }
    static void WithService(string name, uint access, Action<IntPtr> action) {
        IntPtr scm=Manager(1), service=IntPtr.Zero;
        try {
            service=OpenServiceW(scm,name,access);
            if(service==IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
            action(service);
        } finally {
            // Handles came from successful Open/Create calls; no policy is changed on close.
            if(service!=IntPtr.Zero) CloseServiceHandle(service);
            CloseServiceHandle(scm);
        }
    }
    public static void CreateOwn(string name, string binaryCommand) {
        IntPtr scm=Manager(3), service=IntPtr.Zero;
        try {
            service=CreateServiceW(scm,name,name+" (lab only)",
                0x0004,0x0010,2,1,binaryCommand,null,IntPtr.Zero,null,
                @"NT AUTHORITY\LocalService",null);
            if(service==IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
        } finally {
            if(service!=IntPtr.Zero) CloseServiceHandle(service);
            CloseServiceHandle(scm);
        }
    }
    public static void ConfigureOwn(string name) {
        WithService(name,2,delegate(IntPtr h) {
            IntPtr names=Marshal.StringToHGlobalUni("SeChangeNotifyPrivilege\0\0");
            try {
                PrivilegesInfo privileges=new PrivilegesInfo {Names=names};
                if(!SetPrivileges(h,6,ref privileges)) throw new Win32Exception(Marshal.GetLastWin32Error());
            } finally { Marshal.FreeHGlobal(names); }
        });
    }
    public static void StartOwn(string name, string[] args) {
        WithService(name,0x0010,delegate(IntPtr h) {
            if(!StartServiceW(h,args.Length,args)) throw new Win32Exception(Marshal.GetLastWin32Error());
        });
    }
    public static void StopOwn(string name) {
        WithService(name,0x0020,delegate(IntPtr h) {
            Status status;
            if(!ControlService(h,1,out status)) {
                int error=Marshal.GetLastWin32Error();
                if(error!=1062) throw new Win32Exception(error); // already stopped
            }
        });
    }
    public static void DeleteOwn(string name) {
        WithService(name,0x10000,delegate(IntPtr h) {
            if(!DeleteService(h)) throw new Win32Exception(Marshal.GetLastWin32Error());
        });
    }
    public static void CreateSecureDirectory(string path) {
        IntPtr descriptor=IntPtr.Zero; uint size;
        // Atomic creation with protected ACL: no writable inherited ProgramData ACL gap.
        if(!ConvertStringSecurityDescriptorToSecurityDescriptorW(
            "O:BAG:BAD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)",1,out descriptor,out size))
            throw new Win32Exception(Marshal.GetLastWin32Error());
        try {
            SecurityAttributes attributes=new SecurityAttributes {
                Length=Marshal.SizeOf(typeof(SecurityAttributes)), Descriptor=descriptor,
                InheritHandle=false };
            if(!CreateDirectoryW(path,ref attributes))
                throw new Win32Exception(Marshal.GetLastWin32Error()); // includes collision
        } finally { LocalFree(descriptor); }
    }
}
