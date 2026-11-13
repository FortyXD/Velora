//! Private stdio bridge. Quickshell owns its lifetime; no resident model or daemon at login.
use anyhow::Result;
use serde_json::{json, Value};
use tokio::{
    io::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader},
    sync::mpsc,
};
use velora_agentd::{
    provider,
    task::{Decision, Session, Task},
    transaction, Context, PROTOCOL,
};

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<()> {
    unsafe {
        libc::prctl(libc::PR_SET_DUMPABLE, 0);
    }
    let _journal_lease = transaction::lease().await?;
    let recovery = transaction::call("recover", json!({})).await?;
    let (events, mut output) = mpsc::channel::<Value>(256);
    let writer = tokio::spawn(async move {
        let mut stdout = tokio::io::stdout();
        while let Some(value) = output.recv().await {
            if stdout
                .write_all(format!("{value}\n").as_bytes())
                .await
                .is_err()
            {
                break;
            }
            let _ = stdout.flush().await;
        }
    });
    events
        .send(json!({"type":"hello","protocol":PROTOCOL}))
        .await?;
    for state in recovery["transactions"].as_array().into_iter().flatten() {
        let mut event = state.clone();
        event["type"] = json!("transaction");
        events.send(event).await?;
    }
    let (requests, mut incoming) = mpsc::channel(16);
    tokio::spawn(async move {
        let mut input = BufReader::new(tokio::io::stdin());
        loop {
            let mut line = String::new();
            match (&mut input)
                .take(1024 * 1024 + 1)
                .read_line(&mut line)
                .await
            {
                Ok(n) if n > 0 && n <= 1024 * 1024 => {
                    if requests.send(line).await.is_err() {
                        break;
                    }
                }
                _ => break,
            }
        }
    });
    let mut context = Context::default();
    let mut session = Session::default();
    let mut job: Option<tokio::task::JoinHandle<Session>> = None;
    let mut decisions: Option<mpsc::Sender<Decision>> = None;
    let mut active = 0u64;
    let mut active_tx: Option<String> = None;
    let mut highest_id = 0u64;
    let runtime = std::sync::Arc::new(provider::ModelProvider::default());
    let mut last_use = std::time::Instant::now();
    let mut terminate = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())?;
    loop {
        tokio::select! {
            // Reap a completed task before accepting the next configure/submit.
            // The shell can send it immediately after observing "finished".
            biased;
            _=terminate.recv()=>break,

            _=tokio::time::sleep(std::time::Duration::from_secs(30)),if job.is_none()=>{
                if last_use.elapsed().as_secs()>if context.on_battery{60}else{300} || low_memory(){runtime.stop().await;}
            },
            completed=async {match job.as_mut(){Some(j)=>Some(j.await),None=>std::future::pending().await}},if job.is_some()=>{
                job=None;decisions=None;last_use=std::time::Instant::now();if let Some(Ok(saved))=completed{session=saved;active_tx=None;}else{recover_active(&mut active_tx, active, &events).await;let _=events.send(json!({"type":"error","task":active,"message":"Task interrupted; recovery attempted"})).await;let _=events.send(json!({"type":"finished","task":active})).await;}
            },
            read=incoming.recv()=>{
                let Some(line)=read else {break;};
                let request:Value=match serde_json::from_str(&line){Ok(v)=>v,Err(_)=>{events.send(json!({"type":"error","message":"Invalid protocol message"})).await?;continue;}};
                let id=request["id"].as_u64().unwrap_or(0);let p=&request["params"];
                if id==0||id<=highest_id {
                    events.send(json!({"type":"response","id":id,"ok":false,"error":"Request ID must increase; repeated delivery was not executed"})).await?;continue;
                }
                highest_id=id;
                let method=request["method"].as_str().unwrap_or("");
                let result:Result<Value>=match method {
                    "configure"=>{
                        if job.is_some(){Err(anyhow::anyhow!("Stop the active task before changing its configuration"))}
                        else {match serde_json::from_value::<Context>(p.clone()){Ok(c)=>{
                            if c.policy==0||c.locked {session=Session::default();runtime.stop().await;}
                            if c.profile.gpu!=context.profile.gpu {runtime.stop().await;}
                            context=c;Ok(json!({}))},Err(_)=>Err(anyhow::anyhow!("Invalid assistant configuration"))}}
                    },
                    "context"=>{
                        context.locked=p["locked"].as_bool().unwrap_or(true);
                        context.on_battery=p["on_battery"].as_bool().unwrap_or(true);
                        if context.locked {if let Some(j)=job.take(){j.abort();let _=j.await;}recover_active(&mut active_tx, active, &events).await;runtime.stop().await;decisions=None;session=Session::default();context.selection.clear();context.profile.key.clear();events.send(json!({"type":"cancelled","task":active})).await?;}
                        Ok(json!({}))
                    },
                    "cancel"|"reset"=>{
                        if let Some(j)=job.take(){j.abort();let _=j.await;}recover_active(&mut active_tx, active, &events).await;decisions=None;session=Session::default();
                        events.send(json!({"type":"cancelled","task":active})).await?;Ok(json!({}))
                    },
                    "approve"=>{if p["task"].as_u64()==Some(active){if let Some(tx)=&decisions{let _=tx.send(Decision{id:p["approval"].as_str().unwrap_or("").into(),allow:p["allow"]==true}).await;}}Ok(json!({}))},
                    "surface_ready"=>{if p["task"].as_u64()==Some(active)&&p["token"].as_str().is_some_and(|s|s.starts_with("surface:")){if let Some(tx)=&decisions{let _=tx.send(Decision{id:p["token"].as_str().unwrap().into(),allow:true}).await;}}Ok(json!({}))},
                    "restore"=>{
                        if job.is_some() || context.locked || context.policy==0 {Err(anyhow::anyhow!("Stop the task and unlock the assistant before restoring a conversation"))}
                        else {match Session::restore(&p["messages"]) {Ok(restored)=>{session=restored;context.selection.clear();Ok(json!({}))},Err(error)=>Err(error)}}
                    },
                    "selection"=>{if job.is_some(){Err(anyhow::anyhow!("Stop the active task before changing the selection"))}else{context.selection=p["paths"].as_array().into_iter().flatten().filter_map(Value::as_str).take(100).map(str::to_owned).collect();Ok(json!({}))}},
                    "submit"|"probe"|"pull"=> {
                        if job.is_some() { Err(anyhow::anyhow!("A task is already running")) }
                        else if context.locked || context.policy == 0 { Err(anyhow::anyhow!("Assistant is disabled or locked")) }
                        else { (async {
                            let mut ctx = context.clone();
                            if p["strong"] == true && !ctx.profile.strong_model.is_empty() { ctx.profile.model = ctx.profile.strong_model.clone(); }
                            let state = if method == "submit" {
                                anyhow::ensure!(matches!(p["intent"].as_str().unwrap_or("chat"), "chat" | "action"), "Invalid request intent");
                                if p.get("tool").is_some() { anyhow::ensure!(p["tool"]["name"] == "terminal_run" && p["intent"] == "action", "Direct tools require an explicit action request"); }
                                Some(transaction::call("begin", json!({"submission_id":p["submission_id"],"conversation_id":p["conversation_id"],"budget":ctx.rollback_budget_bytes})).await?)
                            } else { None };
                            active = id;
                            active_tx = state.as_ref().and_then(|s| s["transaction_id"].as_str()).map(str::to_owned);
                            let (tx, rx) = mpsc::channel(8); decisions = Some(tx);
                            let saved = std::mem::take(&mut session); let emit = events.clone();
                            if method == "submit" {
                                let task = Task::new(id, p["text"].as_str().unwrap_or("").into(), p["extended"] == true, ctx, emit, rx, runtime.clone(), p);
                                job = Some(tokio::spawn(task.run(saved)));
                            } else {
                                let pull = method == "pull"; let runtime = runtime.clone();
                                job = Some(tokio::spawn(async move {
                                    let result = async {runtime.prepare(&ctx.profile,ctx.policy,ctx.on_battery).await?;if pull{provider::pull(&ctx.profile,&emit,id).await?;}provider::probe(&ctx.profile).await}.await;
                                    match result {Ok(value)=>{let _=emit.send(json!({"type":"capabilities","task":id,"result":value})).await;},Err(error)=>{let _=emit.send(json!({"type":"error","task":id,"message":error.to_string()})).await;}}
                                    let _=emit.send(json!({"type":"finished","task":id})).await;saved
                                }));
                            }
                            Ok(json!({"task":id,"transaction_id":active_tx,"submission_id":p["submission_id"],"conversation_id":p["conversation_id"]}))
                        }).await }
                    },
                    "transactions" => {
                        if context.locked { Err(anyhow::anyhow!("Unlock before reading transaction history")) }
                        else { transaction::call("list", json!({})).await }
                    },
                    "rollback" | "delete_checkpoint" => {
                        if job.is_some() || context.locked || context.policy == 0 { Err(anyhow::anyhow!("Stop the active task and unlock before changing a checkpoint")) }
                        else {
                            match transaction::call(if method == "rollback" {"rollback"} else {"delete"}, json!({"transaction_id":p["transaction_id"],"confirmed":p["confirmed"]})).await {
                                Ok(state) => { let mut event = state.clone(); event["type"] = json!("transaction"); event["task"] = json!(active); let _ = events.send(event).await; session = Session::default(); Ok(state) },
                                Err(error) => Err(error),
                            }
                        }
                    },
                    "status"=>Ok(json!({"running":job.is_some(),"model":context.profile.model,"locked":context.locked})),
                    _=>Err(anyhow::anyhow!("Unknown protocol method")),
                };
                let response=match result {Ok(value)=>json!({"type":"response","id":id,"ok":true,"result":value}),Err(error)=>json!({"type":"response","id":id,"ok":false,"error":error.to_string()})};events.send(response).await?;
            }
        }
    }
    if let Some(j) = job {
        j.abort();
        let _ = j.await;
    }
    recover_active(&mut active_tx, active, &events).await;
    runtime.stop().await;
    drop(decisions);
    drop(events);
    writer.await?;
    // The blocking stdin reader cannot be cancelled while its parent holds the pipe.
    // All owned jobs and subprocess groups have already been stopped.
    std::process::exit(0)
}

fn low_memory() -> bool {
    std::fs::read_to_string("/proc/meminfo")
        .ok()
        .and_then(|text| {
            text.lines()
                .find(|l| l.starts_with("MemAvailable:"))
                .and_then(|line| line.split_whitespace().nth(1))
                .and_then(|n| n.parse::<u64>().ok())
        })
        .is_some_and(|kb| kb < 512 * 1024)
}

async fn recover_active(
    transaction_id: &mut Option<String>,
    task: u64,
    events: &mpsc::Sender<Value>,
) {
    if let Some(id) = transaction_id.take() {
        let status = transaction::call("status", json!({"transaction_id":id})).await;
        if status.as_ref().is_ok_and(|s| {
            !matches!(
                s["state"].as_str(),
                Some("running" | "preparing" | "rolling_back")
            )
        }) {
            return;
        }
        let mut state = match transaction::call("rollback", json!({"transaction_id":id})).await {
            Ok(state) => state,
            Err(error) => {
                json!({"transaction_id":id,"state":"rollback_conflict","rollback_available":true,"conflicts":[],"error":error.to_string()})
            }
        };
        state["type"] = json!("transaction");
        state["task"] = json!(task);
        let _ = events.send(state).await;
    }
}
