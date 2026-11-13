use centurions_editor::store;
use centurions_format::{Edit, Result, inspect};
use serde_json::{Value, json};
use std::path::Path;

fn main() {
    match run(std::env::args().skip(1).collect()) {
        Ok(value) => println!("{}", serde_json::to_string_pretty(&value).unwrap()),
        Err(error) => {
            eprintln!("{error}");
            std::process::exit(1);
        }
    }
}

fn run(args: Vec<String>) -> Result<Value> {
    let arg = |index: usize| {
        args.get(index)
            .map(String::as_str)
            .ok_or_else(|| help().to_string())
    };
    match arg(0)? {
        "micro" if args.len() == 4 => {
            let spec = serde_json::from_slice(&std::fs::read(arg(2)?).map_err(|e| e.to_string())?)
                .map_err(|e| e.to_string())?;
            centurions_editor::connected::create(Path::new(arg(1)?), Path::new(arg(3)?), &spec)
        }
        "records" if args.len() == 2 => {
            let (project, files) = store::open(Path::new(arg(1)?))?;
            centurions_format::authoring::catalogue(&project, &files)
        }
        "record" if args.len() == 4 => {
            let (project, files) = store::open(Path::new(arg(1)?))?;
            let files = centurions_format::apply(&project, &files)?;
            let family = serde_json::from_value(json!(arg(2)?)).map_err(|e| e.to_string())?;
            centurions_format::authoring::inspect(
                &files,
                family,
                arg(3)?.parse().map_err(|_| "invalid record ID")?,
            )
        }
        "allocate" if args.len() == 5 => {
            let source = Path::new(arg(1)?);
            let (project, files) = store::open(source)?;
            let family = serde_json::from_value(json!(arg(2)?)).map_err(|e| e.to_string())?;
            let (next, id) = centurions_format::authoring::allocate(
                &project,
                &files,
                family,
                arg(3)?.parse().map_err(|_| "invalid seed ID")?,
            )?;
            store::save_as(&next, &files, source, Path::new(arg(4)?))?;
            Ok(json!({"family":family,"id":id,"project":arg(4)?}))
        }
        "new" if args.len() == 4 => {
            centurions_editor::minimal::create(Path::new(arg(1)?), Path::new(arg(2)?), arg(3)?)
        }
        "help" | "--help" | "-h" => Ok(json!({"usage":help()})),
        "import" if args.len() == 3 => {
            let project = store::import(Path::new(arg(1)?), Path::new(arg(2)?))?;
            Ok(json!({"imported_files":project.files.len(),"project":arg(2)?}))
        }
        "export" if args.len() == 3 => store::export(Path::new(arg(1)?), Path::new(arg(2)?)),
        "inspect" if args.len() == 2 => {
            let (project, files) = store::open(Path::new(arg(1)?))?;
            let output = centurions_format::apply(&project, &files)?;
            let mut report = inspect::project(&output);
            report["origin"] = serde_json::to_value(&project.origin).map_err(|e| e.to_string())?;
            report["native"] = serde_json::to_value(&project.native).map_err(|e| e.to_string())?;
            report["files"] = json!(project.files);
            Ok(report)
        }
        "message" | "story" | "map" if args.len() == 3 => {
            let (project, files) = store::open(Path::new(arg(1)?))?;
            let files = centurions_format::apply(&project, &files)?;
            let id = arg(2)?.parse::<usize>().map_err(|e| e.to_string())?;
            match arg(0)? {
                "message" => inspect::message(&files, id),
                "story" => inspect::story(&files, id),
                _ => inspect::map(&files, id),
            }
        }
        "edit" if args.len() == 4 => {
            let source = Path::new(arg(1)?);
            let (project, files) = store::open(source)?;
            let changes: Vec<Edit> =
                serde_json::from_slice(&std::fs::read(arg(2)?).map_err(|e| e.to_string())?)
                    .map_err(|e| e.to_string())?;
            let next = centurions_format::update(&project, &files, changes)?;
            store::save_as(&next, &files, source, Path::new(arg(3)?))?;
            Ok(json!({"project":arg(3)?,"edited_fields":next.edits.len()}))
        }
        _ => Err(help().into()),
    }
}

fn help() -> &'static str {
    "centurions-editor import LEVEL_FOLDER NEW_PROJECT\ncenturions-editor export PROJECT NEW_LEVEL_FOLDER\ncenturions-editor inspect PROJECT\ncenturions-editor message|story|map PROJECT ZERO_BASED_ID\ncenturions-editor edit PROJECT CHANGES_JSON NEW_PROJECT\ncenturions-editor new UNCHANGED_TEMPLATE_PROJECT NEW_PROJECT STAGE_NAME\ncenturions-editor records PROJECT\ncenturions-editor record PROJECT FAMILY ID\ncenturions-editor allocate PROJECT FAMILY IMPORTED_SEED_ID NEW_PROJECT\ncenturions-editor micro UNCHANGED_TEMPLATE_PROJECT SPEC_JSON NEW_PROJECT"
}
