//! One process, one editable snapshot. Disk checkpoints remain immutable.
use crate::{minimal, store};
use centurions_format::{Edit, Files, Project, Result, digest, inspect, text};
use serde::Deserialize;
use serde_json::{Value, json};
use std::path::{Path, PathBuf};

pub const PROTOCOL: u32 = 1;
/// The requests and replies the workbench is written for. A change to an operation, an edit or a reply the workbench reads
/// raises it here and in `godot/src/native_bridge.gd`, and the workbench refuses an adapter that reports another number.
pub const INTERFACE: u32 = 16;

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Request {
    pub protocol: u32,
    pub id: u64,
    pub operation: Operation,
}

#[derive(Deserialize)]
#[serde(tag = "op", rename_all = "snake_case", deny_unknown_fields)]
pub enum Operation {
    CreateTrigger {
        expected_revision: u64,
        map: usize,
        x: usize,
        y: usize,
    },
    PlaceTrigger {
        expected_revision: u64,
        id: usize,
        x: usize,
        y: usize,
        chance: i16,
        #[serde(default)]
        remove: bool,
        #[serde(default)]
        follow: bool,
    },
    AuthoredRecords,
    AuthoredRecord {
        family: centurions_format::RecordFamily,
        id: usize,
    },
    AllocateRecord {
        expected_revision: u64,
        family: centurions_format::RecordFamily,
        seed: usize,
    },
    AuthorConnectedMission {
        expected_revision: u64,
        spec: Box<centurions_format::connected::MissionSpec>,
    },
    Describe,
    SetInstallation {
        path: PathBuf,
    },
    Open {
        path: PathBuf,
    },
    Import {
        source: PathBuf,
        destination: PathBuf,
        expected_revision: u64,
    },
    New {
        template: PathBuf,
        destination: PathBuf,
        name: String,
        expected_revision: u64,
    },
    Inspect,
    Messages {
        offset: usize,
        limit: usize,
        query: String,
    },
    Message {
        id: usize,
    },
    Stories {
        offset: usize,
        limit: usize,
    },
    Story {
        id: usize,
    },
    Program {
        family: centurions_format::ScriptFamily,
        id: usize,
        branch: u8,
    },
    ProgramBytes {
        family: centurions_format::ScriptFamily,
        id: usize,
    },
    Map {
        id: usize,
    },
    CombatCatalogue {
        monsters: bool,
        offset: usize,
        query: String,
    },
    CombatRecord {
        monsters: bool,
        id: usize,
    },
    TextCheck {
        text: String,
    },
    Search {
        query: String,
        #[serde(default)]
        families: Vec<String>,
        #[serde(default = "search_limit")]
        limit: usize,
    },
    Uses {
        kind: String,
        id: i64,
    },
    Flow {
        family: centurions_format::ScriptFamily,
        id: usize,
    },
    ExtraImpact {
        record: usize,
    },
    Problems {
        #[serde(default)]
        installation: std::path::PathBuf,
    },
    Shop {
        id: usize,
    },
    Item {
        id: usize,
    },
    Items,
    Calendar,
    AddMap {
        expected_revision: u64,
        copy_of: Option<usize>,
        tile: i16,
        floor: bool,
        objects: bool,
        triggers: bool,
        regions: bool,
    },
    MapReferences {
        map: usize,
    },
    MapReview {
        copy_of: Option<usize>,
        floor: bool,
        objects: bool,
        triggers: bool,
        regions: bool,
    },
    ItemNames {
        installation: PathBuf,
    },
    Icons {
        ids: Vec<i16>,
        installation: PathBuf,
    },
    VaultList {
        installation: PathBuf,
    },
    VaultAdd {
        ids: Vec<usize>,
        installation: PathBuf,
    },
    VaultRemove {
        keys: Vec<String>,
    },
    VaultCopy {
        expected_revision: u64,
        keys: Vec<String>,
        installation: PathBuf,
    },
    Names {
        installation: PathBuf,
    },
    Rewards,
    Sound {
        id: i16,
        installation: PathBuf,
    },
    Picture {
        id: i16,
        installation: PathBuf,
    },
    ScrollTexts,
    NoteLabels,
    Notes,
    Resources {
        installation: PathBuf,
    },
    ImportPrepare {
        kind: String,
        path: PathBuf,
        id: i16,
        #[serde(default)]
        options: Value,
        installation: PathBuf,
    },
    ExportResource {
        kind: String,
        id: i16,
        destination: PathBuf,
        installation: PathBuf,
    },
    ScrollText {
        id: i16,
    },
    Apply {
        expected_revision: u64,
        edits: Vec<Edit>,
    },
    Undo {
        expected_revision: u64,
    },
    Redo {
        expected_revision: u64,
    },
    SaveAs {
        expected_revision: u64,
        destination: PathBuf,
    },
    Export {
        expected_revision: u64,
        destination: PathBuf,
    },
    Artwork {
        map: usize,
        installation: PathBuf,
    },
    CheckReceipt {
        path: PathBuf,
    },
}

fn search_limit() -> usize {
    6
}

struct Document {
    project: Project,
    files: Files,
    path: PathBuf,
    saved: String,
    undo: Vec<Project>,
    redo: Vec<Project>,
}

pub struct Session {
    document: Option<Document>,
    revision: u64,
    cache: PathBuf,
    preferences: Option<PathBuf>,
}

/// What the project holds, counted from the tables the summary lists.
fn contents(summary: &Value) -> Value {
    let rows = |file: &str| {
        summary["tables"]
            .as_array()
            .and_then(|tables| tables.iter().find(|table| table["file"] == file))
            .and_then(|table| table["complete_records"].as_u64())
            .unwrap_or(0)
    };
    let stages = summary["stages"].as_array();
    json!({
        "maps": summary["maps"],
        "stages": stages.map_or(0, Vec::len),
        "stages_in_use": stages.map_or(0, |all| all.iter().filter(|stage| stage["active"] == true).count()),
        "walking_tables": rows("Data DD"),
        "stories": rows("Data ED3"),
        "messages": rows("Data SD2"),
        "choices": rows("Data ED"),
        "typed": rows("Data ED2"),
        "battles": rows("Data BD"),
        "calendar": rows("Data TD3"),
        "monsters": rows("Data MD"),
        "rewards": rows("Data TD"),
    })
}

fn identity(project: &Project) -> String {
    digest(&serde_json::to_vec(project).expect("serializable project"))
}

impl Session {
    pub fn new(cache: PathBuf) -> Self {
        Self {
            document: None,
            revision: 0,
            cache,
            preferences: None,
        }
    }

    pub fn with_preferences(cache: PathBuf, preferences: PathBuf) -> Self {
        let mut session = Self::new(cache);
        session.preferences = Some(preferences);
        session
    }

    fn expect(&self, revision: u64) -> Result<()> {
        if self.revision != revision {
            return Err(format!(
                "stale revision {revision}; current revision is {}",
                self.revision
            ));
        }
        Ok(())
    }

    fn document(&self) -> Result<&Document> {
        self.document.as_ref().ok_or("open a project first".into())
    }

    fn activate(&mut self, path: &Path) -> Result<Value> {
        let (project, files) = store::open(path)?;
        let path = crate::paths::checked_existing(path)?;
        let saved = identity(&project);
        self.document = Some(Document {
            project,
            files,
            path,
            saved,
            undo: vec![],
            redo: vec![],
        });
        self.revision += 1;
        let summary = self.summary()?;
        self.remember(&summary);
        Ok(summary)
    }

    /// Records the open project in the settings file's recent list. A settings
    /// file that cannot be written never fails the operation that opened it.
    fn remember(&self, summary: &Value) {
        let (Some(target), Ok(d)) = (self.preferences.as_ref(), self.document()) else {
            return;
        };
        let (origin, label) = match &d.project.origin {
            centurions_format::model::Origin::Imported { label } => ("imported", label.clone()),
            centurions_format::model::Origin::MinimalTemplate { label, .. } => {
                ("minimal_template", label.clone())
            }
        };
        let notices = summary["warnings"]
            .as_array()
            .map(|all| {
                all.iter()
                    .filter_map(|n| n.as_str().map(str::to_string))
                    .collect()
            })
            .unwrap_or_default();
        let entry = crate::preferences::Recent {
            path: summary["path"]
                .as_str()
                .unwrap_or_default()
                .trim_start_matches(r"\\?\")
                .to_string(),
            name: d
                .project
                .native
                .as_ref()
                .map_or_else(|| label.clone(), |native| native.name.clone()),
            origin: origin.into(),
            label,
            version: u64::from(d.project.version),
            edits: d.project.edits.len() as u64,
            source_files: d.project.files.len() as u64,
            saved: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map_or(0, |elapsed| elapsed.as_secs()),
            contents: summary["contents"].clone(),
            notices,
        };
        let _ = crate::preferences::remember(target, entry);
    }

    fn effective(&self) -> Result<Files> {
        let d = self.document()?;
        centurions_format::apply(&d.project, &d.files)
    }

    fn summary(&self) -> Result<Value> {
        let d = self.document()?;
        let files = self.effective()?;
        let mut v = inspect::project(&files);
        // Include inactive existing rows without allocating native records.
        let stages = files
            .get("Data Mission")
            .map(|b| {
                b.as_chunks::<464>()
                    .0
                    .iter()
                    .enumerate()
                    .map(|(id, row)| {
                        json!({"id":id,"name":text::decode(&row[7..7+usize::from(row[6])]),
                   "x":i16::from_be_bytes([row[0],row[1]]), "y":i16::from_be_bytes([row[2],row[3]]),
                   "map":i16::from_be_bytes([row[4],row[5]]),
                   "start_script":i16::from_be_bytes([row[262],row[263]]), "active":row[6]!=0})
                    })
                    .collect::<Vec<_>>()
            })
            .unwrap_or_default();
        v["stages"] = json!(stages);
        v["path"] = json!(d.path);
        v["native"] = json!(d.project.native);
        v["origin"] = json!(d.project.origin);
        v["dirty"] = json!(identity(&d.project) != d.saved);
        v["can_undo"] = json!(!d.undo.is_empty());
        v["can_redo"] = json!(!d.redo.is_empty());
        v["source_files"] = json!(d.project.files.len());
        v["allocations"] = json!(d.project.allocations);
        v["diagnostics"] = json!(centurions_format::references::diagnostics(
            &d.project, &files
        ));
        v["version"] = json!(d.project.version);
        v["edits"] = json!(d.project.edits.len());
        let mut kinds = serde_json::Map::new();
        for edit in &d.project.edits {
            let kind = json!(edit)["kind"].as_str().unwrap_or("edit").to_string();
            let count = kinds.get(&kind).and_then(Value::as_u64).unwrap_or(0);
            kinds.insert(kind, json!(count + 1));
        }
        v["edit_kinds"] = Value::Object(kinds);
        let counted = contents(&v);
        v["contents"] = counted;
        v["runtime_acceptance"] = json!("No receipt has been matched to this exact export");
        Ok(v)
    }

    fn accept(&mut self, next: Project) -> Result<Value> {
        let d = self.document()?;
        centurions_format::apply(&next, &d.files)?;
        if identity(&next) != identity(&d.project) {
            let d = self.document.as_mut().unwrap();
            d.undo.push(d.project.clone());
            d.redo.clear();
            d.project = next;
            self.revision += 1;
        }
        self.summary()
    }

    pub fn handle(&mut self, request: Request) -> Value {
        let id = request.id;
        let result = if request.protocol == PROTOCOL {
            self.execute(request.operation)
        } else {
            Err("unsupported adapter protocol".into())
        };
        match result {
            Ok(result) => {
                json!({"protocol":PROTOCOL,"id":id,"ok":true,"revision":self.revision,"result":result})
            }
            Err(error) => json!({"protocol":PROTOCOL,"id":id,"ok":false,"revision":self.revision,
                                "error":{"code":if error.starts_with("stale revision") {"stale_revision"} else {"rejected"},"message":error}}),
        }
    }

    fn execute(&mut self, operation: Operation) -> Result<Value> {
        match operation {
            Operation::CreateTrigger {
                expected_revision,
                map,
                x,
                y,
            } => {
                self.expect(expected_revision)?;
                let d = self.document()?;
                let (next, id) =
                    centurions_format::authoring::create_trigger(&d.project, &d.files, map, x, y)?;
                let summary = self.accept(next)?;
                Ok(json!({"summary":summary,"id":id}))
            }
            Operation::PlaceTrigger {
                expected_revision,
                id,
                x,
                y,
                chance,
                remove,
                follow,
            } => {
                self.expect(expected_revision)?;
                let d = self.document()?;
                let next = centurions_format::authoring::place_trigger(
                    &d.project,
                    &d.files,
                    &centurions_format::authoring::TriggerPlacement {
                        id,
                        x,
                        y,
                        chance,
                        remove,
                        follow,
                    },
                )?;
                let summary = self.accept(next)?;
                Ok(json!({"summary":summary,"id":id}))
            }
            Operation::AuthoredRecords => {
                let d = self.document()?;
                centurions_format::authoring::catalogue(&d.project, &d.files)
            }
            Operation::AuthoredRecord { family, id } => {
                centurions_format::authoring::inspect(&self.effective()?, family, id)
            }
            Operation::AllocateRecord {
                expected_revision,
                family,
                seed,
            } => {
                self.expect(expected_revision)?;
                let d = self.document()?;
                let (next, id) =
                    centurions_format::authoring::allocate(&d.project, &d.files, family, seed)?;
                let summary = self.accept(next)?;
                Ok(json!({"summary":summary,"family":family,"id":id}))
            }
            Operation::AuthorConnectedMission {
                expected_revision,
                spec,
            } => {
                self.expect(expected_revision)?;
                let d = self.document()?;
                let (next, recipe) =
                    centurions_format::connected::build(&d.project, &d.files, &spec)?;
                let summary = self.accept(next)?;
                Ok(json!({"summary":summary,"recipe":recipe}))
            }
            Operation::Describe => Ok(
                json!({"protocol":PROTOCOL,"application":"New Centurions Scenario Editor",
                "checkpoint_version":centurions_format::VERSION,"interface":INTERFACE,"open":self.document.is_some(),
                "settings_file":self.preferences,
                "preferences":self.preferences.as_ref().map(|path|crate::preferences::load(path).map(|p|json!(p)).unwrap_or_else(|e|json!({"installation":"","warning":e}))),
                "authorable":centurions_format::AUTHORABLE}),
            ),
            Operation::SetInstallation { path } => {
                let target = self
                    .preferences
                    .as_ref()
                    .ok_or("preferences are unavailable in this session")?;
                Ok(json!(crate::preferences::save(target, &path)?))
            }
            Operation::Open { path } => self.activate(&path),
            Operation::Import {
                source,
                destination,
                expected_revision,
            } => {
                self.expect(expected_revision)?;
                store::import(&source, &destination)?;
                self.activate(&destination)
            }
            Operation::New {
                template,
                destination,
                name,
                expected_revision,
            } => {
                self.expect(expected_revision)?;
                minimal::create(&template, &destination, &name)?;
                self.activate(&destination)
            }
            Operation::Inspect => self.summary(),
            Operation::Messages {
                offset,
                limit,
                query,
            } => {
                if !(1..=128).contains(&limit) {
                    return Err("page limit must be 1..128".into());
                }
                let f = self.effective()?;
                let count = f.get("Data SD2").map_or(0, |b| b.len() / 256);
                let query = query.to_lowercase();
                let rows = (0..count)
                    .map(|id| inspect::message(&f, id))
                    .collect::<Result<Vec<_>>>()?;
                let filtered: Vec<_> = rows
                    .into_iter()
                    .filter(|v| {
                        v["text"]
                            .as_str()
                            .unwrap_or("")
                            .to_lowercase()
                            .contains(&query)
                    })
                    .collect();
                Ok(
                    json!({"total":filtered.len(),"offset":offset,"rows":filtered.into_iter().skip(offset).take(limit).collect::<Vec<_>>()}),
                )
            }
            Operation::Search {
                query,
                families,
                limit,
            } => centurions_format::navigation::search(
                &self.effective()?,
                &query,
                &families,
                limit.clamp(1, 128),
            ),
            Operation::Uses { kind, id } => {
                centurions_format::navigation::uses(&self.effective()?, &kind, id)
            }
            Operation::ExtraImpact { record } => {
                centurions_format::extras::impact(&self.effective()?, record)
            }
            Operation::Flow { family, id } => {
                centurions_format::navigation::flow(&self.effective()?, family, id)
            }
            Operation::Item { id } => centurions_format::items::view(&self.effective()?, id),
            Operation::ItemNames { installation } => {
                crate::media::item_names(&self.effective()?, &installation)
            }
            Operation::Icons { ids, installation } => {
                crate::media::icons(&self.effective()?, &ids, &installation, &self.cache)
            }
            Operation::VaultList { installation } => {
                let dir = crate::vault::folder(self.preferences.as_deref())?;
                crate::vault::list(&dir, &self.effective()?, &installation, &self.cache)
            }
            Operation::VaultAdd { ids, installation } => {
                let dir = crate::vault::folder(self.preferences.as_deref())?;
                let source = match &self.document()?.project.origin {
                    centurions_format::Origin::Imported { label }
                    | centurions_format::Origin::MinimalTemplate { label, .. } => label.clone(),
                };
                let files = self.effective()?;
                let source = crate::vault::scenario_name(&source, &files);
                crate::vault::add(&dir, &files, &installation, &ids, &source)
            }
            Operation::VaultRemove { keys } => {
                crate::vault::remove(&crate::vault::folder(self.preferences.as_deref())?, &keys)
            }
            Operation::VaultCopy {
                expected_revision,
                keys,
                installation,
            } => {
                self.expect(expected_revision)?;
                let dir = crate::vault::folder(self.preferences.as_deref())?;
                let chosen = crate::vault::entries(&dir, &keys, &installation)?;
                let d = self.document()?;
                let mut project = d.project.clone();
                let mut ids = vec![];
                for _ in &chosen {
                    let (next, id) = centurions_format::authoring::allocate(
                        &project,
                        &d.files,
                        centurions_format::RecordFamily::Monster,
                        0,
                    )?;
                    project = next;
                    ids.push(id);
                }
                let edits = match ids.first() {
                    Some(first) => crate::vault::copy_edits(
                        &chosen,
                        *first,
                        &centurions_format::apply(&project, &d.files)?,
                        &installation,
                    )?,
                    None => vec![],
                };
                let next = centurions_format::update(&project, &d.files, edits)?;
                let summary = self.accept(next)?;
                Ok(json!({"summary":summary,"ids":ids}))
            }
            Operation::Names { installation } => crate::media::names(&installation),
            Operation::Resources { installation } => {
                crate::imports::list(&self.effective()?, &installation)
            }
            Operation::ImportPrepare {
                kind,
                path,
                id,
                options,
                installation,
            } => crate::imports::prepare(
                &self.effective()?,
                &installation,
                &self.cache,
                &kind,
                &path,
                id,
                &options,
            ),
            Operation::ExportResource {
                kind,
                id,
                destination,
                installation,
            } => crate::imports::export(&self.effective()?, &installation, &kind, id, &destination),
            Operation::Notes => centurions_format::notes::view(&self.effective()?),
            Operation::NoteLabels => centurions_format::resources::note_labels(&self.effective()?),
            Operation::ScrollTexts => {
                centurions_format::resources::scroll_texts(&self.effective()?)
            }
            Operation::ScrollText { id } => {
                centurions_format::resources::scroll_text(&self.effective()?, id)
            }
            Operation::Picture { id, installation } => {
                crate::media::picture_png(&self.effective()?, id, &installation, &self.cache)
            }
            Operation::Sound { id, installation } => {
                crate::media::sound(&self.effective()?, id, &installation, &self.cache)
            }
            Operation::Rewards => centurions_format::record_view::rewards(&self.effective()?),
            Operation::Items => Ok(centurions_format::items::catalogue(&self.effective()?)),
            Operation::Calendar => centurions_format::calendar::view(&self.effective()?),
            Operation::AddMap {
                expected_revision,
                copy_of,
                tile,
                floor,
                objects,
                triggers,
                regions,
            } => {
                self.expect(expected_revision)?;
                let d = self.document()?;
                let edit = centurions_format::maps::prepare(
                    &self.effective()?,
                    copy_of,
                    tile,
                    floor,
                    objects,
                    triggers,
                    regions,
                )?;
                let next = centurions_format::update(&d.project, &d.files, vec![edit])?;
                self.accept(next)
            }
            Operation::MapReferences { map } => {
                let files = self.effective()?;
                Ok(
                    json!({"map":map,"maps":centurions_format::maps::count(&files),
                    "named":centurions_format::maps::references(&files, map)}),
                )
            }
            Operation::MapReview {
                copy_of,
                floor,
                objects,
                triggers,
                regions,
            } => centurions_format::maps::review(
                &self.effective()?,
                copy_of,
                floor,
                objects,
                triggers,
                regions,
            ),
            Operation::Shop { id } => centurions_format::shops::view(&self.effective()?, id),
            Operation::Problems { installation } => {
                let d = self.document()?;
                let files = self.effective()?;
                let mut result = centurions_format::navigation::problems(&d.project, &files)?;
                // A picture, text or animation the game cannot find is a finding of its own.
                let mut missing = crate::media::missing_resources(&files, &installation)?;
                missing.extend(crate::media::name_findings(&files));
                missing.extend(crate::media::icon_findings(&files));
                if !missing.is_empty() {
                    let count = missing.len() as u64;
                    if let Some(list) = result["findings"].as_array_mut() {
                        list.extend(missing);
                    }
                    if let Some(total) = result["counts"]["warnings"].as_u64() {
                        result["counts"]["warnings"] = serde_json::json!(total + count);
                    }
                }
                Ok(result)
            }
            Operation::Message { id } => inspect::message(&self.effective()?, id),
            Operation::Story { id } => inspect::story(&self.effective()?, id),
            Operation::Program { family, id, branch } => {
                centurions_format::scripts::program(&self.effective()?, family, id, branch)
            }
            Operation::ProgramBytes { family, id } => {
                centurions_format::scripts::program_bytes(&self.effective()?, family, id)
            }
            Operation::Stories { offset, limit } => {
                if !(1..=128).contains(&limit) {
                    return Err("page limit must be 1..128".into());
                }
                let f = self.effective()?;
                let count = f.get("Data ED3").map_or(0, |b| b.len() / 42);
                Ok(
                    json!({"total":count,"offset":offset,"rows":(offset.min(count)..offset.min(count).saturating_add(limit).min(count)).map(|id| inspect::story(&f,id)).collect::<Result<Vec<_>>>()?}),
                )
            }
            Operation::Map { id } => inspect::map(&self.effective()?, id),
            Operation::CombatCatalogue {
                monsters,
                offset,
                query,
            } => centurions_format::combat_view::catalogue(
                &self.effective()?,
                monsters,
                offset,
                &query,
            ),
            Operation::CombatRecord { monsters, id } => {
                centurions_format::combat_view::record(&self.effective()?, monsters, id)
            }
            Operation::TextCheck { text: value } => match text::encode(&value) {
                Ok(bytes) => {
                    Ok(json!({"encoded_bytes":bytes.len(),"maximum":255,"valid":bytes.len()<=255}))
                }
                Err(error) => Ok(json!({"valid":false,"error":error,"maximum":255})),
            },
            Operation::Apply {
                expected_revision,
                edits,
            } => {
                self.expect(expected_revision)?;
                if edits.len() > 8100 {
                    return Err("edit batch exceeds one map".into());
                }
                if edits.iter().any(|e| {
                    !centurions_format::authoring::handles(e)
                        && !matches!(
                            e,
                            Edit::Message { .. }
                                | Edit::StageName { .. }
                                | Edit::StageStart { .. }
                                | Edit::Opening { .. }
                                | Edit::Floor { .. }
                                | Edit::ScriptStep { .. }
                                | Edit::WalkingLocation { .. }
                                | Edit::WalkingChance { .. }
                                | Edit::Region { .. }
                                | Edit::MapLook { .. }
                                | Edit::ExtraWord { .. }
                                | Edit::ExtraRow { .. }
                                | Edit::ExtraIndependent { .. }
                                | Edit::ShopStock { .. }
                                | Edit::ShopPrice { .. }
                                | Edit::MonsterField { .. }
                                | Edit::MonsterDescription { .. }
                                | Edit::ItemField { .. }
                                | Edit::ItemDescription { .. }
                                | Edit::EncounterCondition { .. }
                                | Edit::ResourceChange { .. }
                                | Edit::ScrollText { .. }
                                | Edit::ScrollTextRemove { .. }
                                | Edit::ItemName { .. }
                                | Edit::NoteLabel { .. }
                                | Edit::RemoveMap { .. }
                                | Edit::MapNote { .. }
                                | Edit::CalendarEntry { .. }
                                | Edit::MapObject { .. }
                        )
                }) {
                    return Err("operation is reserved for template construction".into());
                }
                let d = self.document()?;
                let next = centurions_format::update(&d.project, &d.files, edits)?;
                self.accept(next)
            }
            Operation::Undo { expected_revision } | Operation::Redo { expected_revision } => {
                self.expect(expected_revision)?;
                let undo = matches!(operation, Operation::Undo { .. });
                let d = self.document.as_mut().ok_or("open a project first")?;
                let next =
                    if undo { d.undo.pop() } else { d.redo.pop() }.ok_or("history is empty")?;
                if undo {
                    d.redo.push(d.project.clone());
                } else {
                    d.undo.push(d.project.clone());
                }
                d.project = next;
                self.revision += 1;
                self.summary()
            }
            Operation::SaveAs {
                expected_revision,
                destination,
            } => {
                self.expect(expected_revision)?;
                let d = self.document()?;
                store::save_as(&d.project, &d.files, &d.path, &destination)?;
                let d = self.document.as_mut().unwrap();
                d.path = crate::paths::checked_existing(&destination)?;
                d.saved = identity(&d.project);
                self.revision += 1;
                let summary = self.summary()?;
                self.remember(&summary);
                Ok(summary)
            }
            Operation::Export {
                expected_revision,
                destination,
            } => {
                self.expect(expected_revision)?;
                let d = self.document()?;
                store::export_snapshot(&d.project, &d.files, &d.path, &destination)
            }
            Operation::Artwork { map, installation } => {
                crate::media::artwork(&self.effective()?, map, &installation, &self.cache)
            }
            Operation::CheckReceipt { path } => {
                let path = crate::paths::checked_existing(&path)?;
                let bytes = std::fs::read(path).map_err(|e| e.to_string())?;
                if bytes.len() > 1024 * 1024 {
                    return Err("receipt is too large".into());
                }
                let receipt: Value = serde_json::from_slice(&bytes).map_err(|e| e.to_string())?;
                let files = self.effective()?;
                let hashes: std::collections::BTreeMap<_, _> =
                    files.iter().map(|(n, b)| (n.clone(), digest(b))).collect();
                let matched = receipt["export_files"] == json!(hashes)
                    && receipt["export_directories"] == json!(self.document()?.project.directories)
                    && receipt["producer"] == "centurions-native-application"
                    && receipt["authority"] == "original_application"
                    && receipt["instruction_patches"] == json!([]);
                Ok(
                    json!({"matched":matched,"startup_status":if matched {receipt["startup_status"].clone()}else{json!("unverified")},
                    "prologue_status":if matched {receipt["prologue_status"].clone()}else{json!("unverified")},
                    "limitation":receipt["prologue_limitation"],"receipt_sha256":digest(&bytes)}),
                )
            }
        }
    }
}
