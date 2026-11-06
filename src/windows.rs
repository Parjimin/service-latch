use service_latch_poc1a::{
    log::EventLog, parse_start_arguments, TestMode, CLEANUP_FAILURE, INTERNAL_FAILURE,
    SERVICE_NAME, STARTUP_FAILURE,
};
use std::ffi::OsString;
use std::io::Write;
use std::path::PathBuf;
use std::sync::{mpsc, OnceLock};
use std::time::Duration;
use windows_service::service::{
    ServiceControl, ServiceControlAccept, ServiceExitCode, ServiceState, ServiceStatus, ServiceType,
};
use windows_service::service_control_handler::{
    self, ServiceControlHandlerResult, ServiceStatusHandle,
};
use windows_service::{define_windows_service, service_dispatcher};

static LOG_DIRECTORY: OnceLock<PathBuf> = OnceLock::new();
define_windows_service!(ffi_service_main, service_main);

pub fn dispatch() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<_> = std::env::args_os().skip(1).collect();
    let [mode, key, directory] = args.as_slice() else {
        return Err("expected --service --log-dir <installed absolute directory>".into());
    };
    let path = PathBuf::from(directory);
    if mode != "--service" || key != "--log-dir" || !path.is_absolute() {
        return Err("invalid service command line".into());
    }
    LOG_DIRECTORY
        .set(path)
        .map_err(|_| "service initialized twice")?;
    service_dispatcher::start(SERVICE_NAME, ffi_service_main)?;
    Ok(())
}

#[derive(Clone, Copy)]
enum StopReason {
    Stop,
    Shutdown,
}

fn report(
    handle: ServiceStatusHandle,
    state: ServiceState,
    exit_code: ServiceExitCode,
) -> windows_service::Result<()> {
    let pending = matches!(
        state,
        ServiceState::StartPending | ServiceState::StopPending
    );
    handle.set_service_status(ServiceStatus {
        service_type: ServiceType::OWN_PROCESS,
        current_state: state,
        controls_accepted: if state == ServiceState::Running {
            ServiceControlAccept::STOP | ServiceControlAccept::SHUTDOWN
        } else {
            ServiceControlAccept::empty()
        },
        exit_code,
        checkpoint: u32::from(pending),
        wait_hint: if pending {
            Duration::from_secs(5)
        } else {
            Duration::ZERO
        },
        process_id: None,
    })
}

fn service_main(arguments: Vec<OsString>) {
    let (sender, receiver) = mpsc::sync_channel(1);
    let handler = move |control| {
        let reason = match control {
            ServiceControl::Interrogate => return ServiceControlHandlerResult::NoError,
            ServiceControl::Stop => StopReason::Stop,
            ServiceControl::Shutdown => StopReason::Shutdown,
            _ => return ServiceControlHandlerResult::NotImplemented,
        };
        match sender.try_send(reason) {
            Ok(()) | Err(mpsc::TrySendError::Full(_)) => ServiceControlHandlerResult::NoError,
            Err(mpsc::TrySendError::Disconnected(_)) => ServiceControlHandlerResult::Other(1062),
        }
    };
    let handle = match service_control_handler::register(SERVICE_NAME, handler) {
        Ok(handle) => handle,
        Err(error) => {
            let _ = writeln!(std::io::stderr(), "RegisterServiceCtrlHandlerExW: {error}");
            std::process::exit(1);
        }
    };
    // No Rust unwind is allowed to escape into the Windows ServiceMain callback.
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        run(handle, receiver, &arguments)
    }));
    let exit = match result {
        Ok(Ok(())) => ServiceExitCode::Win32(0),
        Ok(Err(code)) => code,
        Err(_) => ServiceExitCode::ServiceSpecific(INTERNAL_FAILURE),
    };
    // Exactly one final status report. No service API calls after STOPPED.
    if let Err(error) = report(handle, ServiceState::Stopped, exit) {
        let _ = writeln!(std::io::stderr(), "SetServiceStatus(STOPPED): {error}");
        std::process::exit(1);
    }
}

fn run(
    handle: ServiceStatusHandle,
    receiver: mpsc::Receiver<StopReason>,
    arguments: &[OsString],
) -> Result<(), ServiceExitCode> {
    report(
        handle,
        ServiceState::StartPending,
        ServiceExitCode::Win32(0),
    )
    .map_err(api_exit)?;
    let directory = LOG_DIRECTORY
        .get()
        .ok_or(ServiceExitCode::ServiceSpecific(INTERNAL_FAILURE))?;
    let mut log = EventLog::open(directory).map_err(io_exit)?;
    log.record("starting", 0).map_err(io_exit)?;
    let mode = match parse_start_arguments(arguments) {
        Ok(mode) => mode,
        Err(_) => {
            log.record("invalid_start_arguments", 87).map_err(io_exit)?;
            return Err(ServiceExitCode::Win32(87));
        }
    };
    if mode == TestMode::FailStartup {
        log.record("startup_failed_injected", STARTUP_FAILURE)
            .map_err(io_exit)?;
        return Err(ServiceExitCode::ServiceSpecific(STARTUP_FAILURE));
    }
    report(handle, ServiceState::Running, ServiceExitCode::Win32(0)).map_err(api_exit)?;
    log.record("running", 0).map_err(io_exit)?;
    // No timer, polling, network, IPC listener, work queue or periodic disk writes.
    let reason = receiver.recv().map_err(internal_exit)?;
    report(handle, ServiceState::StopPending, ServiceExitCode::Win32(0)).map_err(api_exit)?;
    log.record(
        match reason {
            StopReason::Stop => "stop_requested",
            StopReason::Shutdown => "shutdown_requested",
        },
        0,
    )
    .map_err(io_exit)?;
    if mode == TestMode::FailCleanup {
        log.record("cleanup_failed_injected", CLEANUP_FAILURE)
            .map_err(io_exit)?;
        return Err(ServiceExitCode::ServiceSpecific(CLEANUP_FAILURE));
    }
    log.record("cleanup_complete", 0).map_err(io_exit)?;
    // log is dropped (file closed) before the final STOPPED report in service_main.
    Ok(())
}

fn io_exit(error: std::io::Error) -> ServiceExitCode {
    ServiceExitCode::Win32(
        error
            .raw_os_error()
            .and_then(|code| u32::try_from(code).ok())
            .filter(|code| *code != 0)
            .unwrap_or(1),
    )
}

fn internal_exit<T>(_error: T) -> ServiceExitCode {
    ServiceExitCode::ServiceSpecific(INTERNAL_FAILURE)
}

fn api_exit(error: windows_service::Error) -> ServiceExitCode {
    match error {
        windows_service::Error::Winapi(error) => io_exit(error),
        _ => ServiceExitCode::ServiceSpecific(INTERNAL_FAILURE),
    }
}
