#[cfg(windows)]
mod windows;

fn main() {
    if std::env::args_os().skip(1).collect::<Vec<_>>() == [std::ffi::OsString::from("--version")] {
        println!("service-latch-poc1a {}", env!("CARGO_PKG_VERSION"));
        return;
    }
    #[cfg(windows)]
    if let Err(error) = windows::dispatch() {
        eprintln!("PoC-1A: {error}");
        std::process::exit(1);
    }
    #[cfg(not(windows))]
    {
        eprintln!("PoC-1A is a Windows service. Only shared unit tests run on this OS.");
        std::process::exit(2);
    }
}
