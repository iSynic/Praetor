use centurions_editor::session::{PROTOCOL, Request, Session};
use serde_json::json;
use std::io::{BufRead, Write};

fn main() {
    let cache = std::env::var_os("CENTURIONS_CACHE_DIR")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|| {
            std::env::current_exe()
                .expect("executable path")
                .parent()
                .unwrap()
                .parent()
                .unwrap()
                .join("centurions-artwork-cache")
        });
    let preferences = std::env::var_os("CENTURIONS_SETTINGS_FILE")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|| {
            std::env::current_exe()
                .unwrap()
                .parent()
                .unwrap()
                .parent()
                .unwrap()
                .join("centurions-editor-settings.json")
        });
    let mut session = Session::with_preferences(cache, preferences);
    let mut output = std::io::stdout().lock();
    for line in std::io::stdin().lock().lines() {
        let Ok(line) = line else {
            break;
        };
        if line.len() > 4 * 1024 * 1024 {
            break;
        }
        let reply = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            match serde_json::from_str::<Request>(&line) {
                Ok(request) => session.handle(request),
                Err(error) => {
                    json!({"protocol":PROTOCOL,"id":null,"ok":false,"error":{"code":"invalid_request","message":error.to_string()}})
                }
            }
        }));
        let poisoned = reply.is_err();
        let reply = reply.unwrap_or_else(|_| json!({"protocol":PROTOCOL,"id":null,"ok":false,"outcome_unknown":true,
            "error":{"code":"session_poisoned","message":"Adapter interrupted; reopen the project"}}));
        if writeln!(output, "{reply}")
            .and_then(|_| output.flush())
            .is_err()
            || poisoned
        {
            break;
        }
    }
}
