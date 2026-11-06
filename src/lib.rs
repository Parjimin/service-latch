//! Shared, OS-independent parts of the PoC. No service mutation APIs.
pub mod log;

use std::ffi::OsString;

pub const SERVICE_NAME: &str = "ServiceLatch.Poc1A.8f61bc537e1c49aaa52ae744ad486ef0";
pub const PROJECT_ID: &str = "8f61bc537e1c49aaa52ae744ad486ef0";
pub const STARTUP_FAILURE: u32 = 1001;
pub const CLEANUP_FAILURE: u32 = 1002;
pub const INTERNAL_FAILURE: u32 = 1003;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum TestMode {
    Normal,
    FailStartup,
    FailCleanup,
}

/// SCM passes the service name as argv[0]. Test arguments apply to ONE start,
/// not to the installed ImagePath and therefore not to subsequent auto-starts.
pub fn parse_start_arguments(args: &[OsString]) -> Result<TestMode, &'static str> {
    match args {
        [name] if name == SERVICE_NAME => Ok(TestMode::Normal),
        [name, flag] if name == SERVICE_NAME && flag == "--fail-startup" => {
            Ok(TestMode::FailStartup)
        }
        [name, flag] if name == SERVICE_NAME && flag == "--fail-cleanup" => {
            Ok(TestMode::FailCleanup)
        }
        _ => Err("invalid SCM service name or start arguments"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fault_modes_are_single_start_explicit_and_exclusive() {
        let args = |flag: &str| vec![SERVICE_NAME.into(), flag.into()];
        assert_eq!(
            parse_start_arguments(&[SERVICE_NAME.into()]),
            Ok(TestMode::Normal)
        );
        assert_eq!(
            parse_start_arguments(&args("--fail-startup")),
            Ok(TestMode::FailStartup)
        );
        assert_eq!(
            parse_start_arguments(&args("--fail-cleanup")),
            Ok(TestMode::FailCleanup)
        );
        assert!(parse_start_arguments(&args("--anything-else")).is_err());
        assert!(parse_start_arguments(&["another-service".into()]).is_err());
        assert!(parse_start_arguments(&[
            SERVICE_NAME.into(),
            "--fail-startup".into(),
            "--fail-cleanup".into()
        ])
        .is_err());
        assert!(parse_start_arguments(&[]).is_err());
    }
}
