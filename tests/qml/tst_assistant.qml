import QtQuick
import QtTest
import "."

TestCase {
    name: "Assistant"
    when: windowShown
    function incoming(v) { Assistant.handle(JSON.stringify(v)); }
    function lastRequest() { return JSON.parse(Assistant.backend.writes[Assistant.backend.writes.length - 1]); }
    function replyLast(result) {
        const request = lastRequest();
        incoming({type:"response", id:request.id, ok:true, result:result ?? {}});
    }
    function runPending() {
        for (let i = 0; i < 6 && !Assistant.busy; i++) replyLast();
        verify(Assistant.busy);
    }
    function connectAndRun() { incoming({type:"hello", protocol:3}); runPending(); }
    function finish() { incoming({type:"finished", task:Assistant.task}); }
    function init() {
        Assistant.cancel(); Assistant.backend.running = false; Assistant.backend.exited(0,0);
        GlobalStates.screenLocked = false;
        Config.options = {assistant:{enabled:true,model:"test",provider:"ollama",endpoint:"http://localhost:11434",vision:false},policies:{ai:2},panelFamily:"ii"};
        ChatStore.deferred = false; ChatStore.failure = ""; ChatStore.waiting = []; ChatStore.saved = ({});
        Ai.nativeGenerating = false;
        SidebarChat.active = false; SidebarChat.fresh();
        Assistant.reset(); Assistant.actionSession = false; Assistant.transactions = ({});
        Assistant.mainShell = true; Assistant.backend.writes = [];
        GlobalStates.overviewOpen = false; GlobalStates.sidebarLeftOpen = false;
    }
    function test_lazy_start_and_complete() {
        verify(Assistant.enabled); verify(!Assistant.backend.running);
        verify(Assistant.submit("hello")); verify(Assistant.backend.running); verify(!Assistant.busy);
        verify(ChatStore.saved[SidebarChat.conversationId]);
        connectAndRun(); verify(Lens.assistantBusy);
        const request = lastRequest();
        compare(request.method, "submit"); compare(request.params.conversation_id, SidebarChat.conversationId);
        compare(request.params.submission_id, SidebarChat.currentReply.submissionId);
        incoming({type:"answer",task:Assistant.task,text:"answer"}); finish();
        verify(!Assistant.busy); verify(!Lens.assistantBusy); compare(Assistant.messages.length,2);
        compare(SidebarChat.messages.length,2); compare(SidebarChat.currentReply.text,"answer");
    }
    function test_storage_ack_precedes_execution_and_deduplicates_enter() {
        ChatStore.deferred = true;
        verify(Assistant.submit("create folder")); verify(Assistant.preparingSubmission);
        verify(!Assistant.backend.running); compare(Assistant.backend.writes.length,0);
        verify(!Assistant.submit("create folder")); compare(SidebarChat.messages.length,2);
        const submission = SidebarChat.currentReply.submissionId;
        ChatStore.acknowledge(); verify(Assistant.backend.running); connectAndRun();
        compare(lastRequest().params.submission_id,submission);
    }
    function test_failed_save_preserves_draft_and_prevents_execution() {
        ChatStore.failure = "disk full"; SidebarChat.draft = "write report";
        verify(SidebarChat.send());
        verify(!Assistant.backend.running); compare(Assistant.backend.writes.length,0);
        compare(SidebarChat.draft,"write report"); compare(SidebarChat.currentReply.status,"error");
        verify(!Assistant.preparingSubmission); verify(!SidebarChat.active);
    }
    function test_launcher_creates_new_chat_preserving_previous_draft() {
        const original = SidebarChat.conversationId; SidebarChat.draft = "unfinished draft";
        verify(Assistant.submit("task one")); const first = SidebarChat.conversationId;
        verify(first !== original); compare(ChatStore.saved[original].draft,"unfinished draft");
        connectAndRun(); finish();
        verify(Assistant.submit("task two")); verify(SidebarChat.conversationId !== first);
        runPending(); compare(SidebarChat.messages.length,2);
        verify(ChatStore.saved[first]);
    }
    function test_sidebar_continues_existing_history() {
        SidebarChat.append({role:"user",text:"past"}); SidebarChat.append({role:"assistant",text:"answer"});
        const id = SidebarChat.conversationId; SidebarChat.draft = "continue";
        verify(SidebarChat.send()); incoming({type:"hello",protocol:3}); replyLast();
        compare(lastRequest().method,"restore"); compare(lastRequest().params.messages[0].content,"past");
        runPending(); compare(SidebarChat.conversationId,id); compare(SidebarChat.messages.length,4);
        compare(SidebarChat.draft,"");
    }
    function test_selected_files_survive_history_restore() {
        Assistant.selectedPaths = ["/example/report.txt"];
        verify(Assistant.submit("read the selected file"));
        incoming({type:"hello",protocol:3}); replyLast();
        compare(lastRequest().method,"restore"); replyLast();
        compare(lastRequest().method,"selection");
        compare(lastRequest().params.paths[0],"/example/report.txt");
        compare(SidebarChat.messages[0].attachments[0],"/example/report.txt");
        runPending();
    }
    function test_launcher_followup_keeps_live_context_and_surface() {
        verify(Assistant.submit("find the report")); connectAndRun();
        incoming({type:"clarification",task:Assistant.task,choices:[{value:"object:1",label:"Report"}]}); finish();
        const id = SidebarChat.conversationId;
        const start = Assistant.backend.writes.length;
        verify(Assistant.submitChoice("object:1","Report")); runPending();
        compare(Assistant.origin,"launcher"); compare(SidebarChat.conversationId,id);
        compare(SidebarChat.messages.length,4);
        verify(!Assistant.backend.writes.slice(start).some(line => JSON.parse(line).method === "restore"));
        incoming({type:"approval",task:Assistant.task,approval:"review"});
        verify(GlobalStates.overviewOpen); verify(!GlobalStates.sidebarLeftOpen); finish();
        verify(Assistant.submitFollowUp("explain it","explain it","launcher")); runPending();
        compare(SidebarChat.conversationId,id); compare(SidebarChat.messages.length,6);
    }
    function test_followup_after_cancel_restores_text_context() {
        Assistant.submit("question"); connectAndRun();
        incoming({type:"delta",task:Assistant.task,text:"Partial"});
        Assistant.cancel(); incoming({type:"cancelled",task:Assistant.task});
        verify(Assistant.submitFollowUp("continue","continue","launcher")); replyLast();
        compare(lastRequest().method,"restore");
        verify(lastRequest().params.messages.some(m => m.content.includes("Partial")));
        runPending();
    }
    function test_cpu_progress_and_truncated_answer_are_not_errors() {
        Assistant.submit("explain"); connectAndRun();
        incoming({type:"phase",task:Assistant.task,phase:"loading"}); compare(SidebarChat.statusText,"Loading the model…");
        incoming({type:"phase",task:Assistant.task,phase:"generating"}); compare(SidebarChat.statusText,"Generating response…");
        incoming({type:"answer",task:Assistant.task,text:"Useful partial answer",truncated:true}); finish();
        compare(SidebarChat.currentReply.text,"Useful partial answer"); verify(SidebarChat.currentReply.truncated);
        compare(SidebarChat.currentReply.status,"done"); compare(SidebarChat.currentReply.error,"");
        verify(ChatStore.saved[SidebarChat.conversationId].messages[1].truncated);
    }
    function test_unexpected_clean_exit_reports_interruption() {
        Assistant.submit("hello"); connectAndRun(); const task = Assistant.task;
        incoming({type:"delta",task:Assistant.task,text:"Partial answer"});
        Assistant.backend.exited(0,0);
        verify(!SidebarChat.busy); compare(SidebarChat.currentReply.status,"error");
        verify(SidebarChat.currentReply.error.length > 0); compare(SidebarChat.currentReply.text,"Partial answer");
        compare(Assistant.streaming,""); compare(Assistant.messages.length,2);
        compare(Assistant.messages[1].text,"Partial answer");
        incoming({type:"finished",task}); Assistant.backend.exited(0,0);
        compare(Assistant.messages.length,2);
    }
    function test_finished_request_rejects_late_events() {
        Assistant.submit("hello"); connectAndRun(); const task = Assistant.task;
        incoming({type:"answer",task,text:"Done"}); finish();
        incoming({type:"delta",task,text:"late"}); incoming({type:"error",task,message:"late error"});
        compare(Assistant.streaming,""); compare(Assistant.problem,""); compare(SidebarChat.currentReply.text,"Done");
    }
    function test_cancelled_configuration_cannot_discard_next_request() {
        Assistant.submit("old request"); incoming({type:"hello",protocol:3});
        const oldConfigure = lastRequest().id;
        Assistant.cancel();
        verify(Assistant.submit("new request")); const newConfigure = lastRequest().id;
        incoming({type:"response",id:oldConfigure,ok:false,error:"stale failure"});
        verify(Assistant.queued !== null); compare(Assistant.problem,"");
        incoming({type:"response",id:newConfigure,ok:true,result:{}}); runPending();
        compare(lastRequest().params.text,"new request");
    }
    function test_cancel_rejects_late_events() {
        Assistant.submit("hello"); connectAndRun(); const task = Assistant.task;
        incoming({type:"delta",task,text:"Useful partial text"});
        Assistant.cancel(); incoming({type:"delta",task,text:"late"}); incoming({type:"approval",task,approval:"evil"});
        compare(Assistant.streaming,""); compare(Assistant.approval,null); verify(Assistant.busy); verify(Assistant.cancelling);
        compare(Assistant.messages.length,2); compare(Assistant.messages[1].text,"Useful partial text");
        verify(!Assistant.submit("next task"));
        incoming({type:"cancelled",task}); verify(!Assistant.busy); verify(!Assistant.cancelling);
        compare(SidebarChat.currentReply.status,"interrupted");
        incoming({type:"finished",task}); Assistant.backend.exited(0,0);
        compare(Assistant.messages.length,2); compare(SidebarChat.currentReply.text,"Useful partial text");
    }
    function test_cancel_before_save_ack_never_executes() {
        ChatStore.deferred = true; Assistant.submit("task"); Assistant.cancel(); ChatStore.acknowledge();
        verify(!Assistant.backend.running); verify(!Assistant.preparingSubmission); compare(Assistant.backend.writes.length,0);
    }
    function test_lock_clears_context_and_invalidates_approval() {
        Assistant.submit("private"); connectAndRun();
        incoming({type:"delta",task:Assistant.task,text:"Private partial text"});
        Assistant.completedSteps=[{result:{path:"/private"}}]; Assistant.selectedPaths=["/private"];
        GlobalStates.screenLocked=true;
        Assistant.backend.exited(0,0);
        verify(!Assistant.backend.running); verify(!Assistant.busy); compare(Assistant.messages.length,0);
        compare(Assistant.streaming,"");
        compare(Assistant.selectedPaths.length,0); compare(Assistant.completedSteps.length,0);
    }
    function test_ui_acknowledgement_follows_overlay_close() {
        Assistant.submit("inspect"); connectAndRun();
        GlobalStates.overviewOpen=true; GlobalStates.sidebarLeftOpen=true;
        incoming({type:"prepare_ui",task:Assistant.task,token:"surface:1:1"});
        verify(!GlobalStates.overviewOpen); verify(!GlobalStates.sidebarLeftOpen); wait(250);
        compare(lastRequest().method,"surface_ready"); compare(lastRequest().params.token,"surface:1:1");
    }
    function test_file_picker_cancel_returns_to_launcher_without_error() {
        for (const family of ["ii", "waffle"]) {
            Config.options = {assistant:{enabled:true,model:"test"},policies:{ai:2},panelFamily:family};
            verify(Assistant.submit("choose a file"));
            if (!Assistant.ready) connectAndRun(); else runPending();
            const task = Assistant.task;
            incoming({type:"delta",task,text:"Choose the report."});
            incoming({type:"prepare_ui",task,token:"surface:picker"});
            verify(!Assistant.panelOpen); verify(!GlobalStates.overviewOpen); verify(!GlobalStates.searchOpen);
            incoming({type:"cancelled",task,reason:"selection_cancelled"});
            verify(Assistant.panelOpen); verify(!SidebarChat.busy); compare(Assistant.problem,"");
            compare(SidebarChat.currentReply.error,""); compare(SidebarChat.currentReply.status,"interrupted");
            compare(SidebarChat.currentReply.text,"Choose the report.\n\nFile selection cancelled.");
            compare(Assistant.messages[Assistant.messages.length - 1].text,SidebarChat.currentReply.text);
            verify(family === "waffle" ? GlobalStates.searchOpen : GlobalStates.overviewOpen);
            const count = Assistant.messages.length;
            incoming({type:"finished",task}); compare(Assistant.messages.length,count);
        }
    }
    function test_failed_request_keeps_partial_answer_in_launcher() {
        Assistant.submit("explain"); connectAndRun(); const task = Assistant.task;
        incoming({type:"delta",task,text:"Useful partial text"});
        incoming({type:"error",task,message:"Provider disconnected"}); finish();
        compare(Assistant.messages[Assistant.messages.length - 1].text,"Useful partial text");
        compare(SidebarChat.currentReply.text,"Useful partial text");
        compare(Assistant.problem,"Provider disconnected");
    }
    function test_foreign_submission_and_failure_do_not_break_search() {
        Assistant.submit("hello"); connectAndRun();
        incoming({type:"approval",task:Assistant.task,submission_id:"foreign"}); compare(Assistant.approval,null);
        incoming({type:"approval",task:Assistant.task+100}); compare(Assistant.approval,null);
        Assistant.backend.exited(1,0); verify(!Assistant.busy); verify(!Lens.assistantBusy); verify(!Assistant.ready);
    }
    function test_old_protocol_cannot_submit() {
        Assistant.submit("task"); incoming({type:"hello",protocol:2});
        verify(!Assistant.ready); verify(!Assistant.backend.running); compare(Assistant.backend.writes.length,0);
        verify(Assistant.problem.length > 0);
    }
    function test_disabled_chat_tool_uses_shared_runtime() {
        Config.options={assistant:{enabled:false,model:"test"},policies:{ai:2}};
        verify(!Assistant.submit("hello")); verify(!Assistant.backend.running);
        const id=SidebarChat.conversationId;
        verify(Assistant.submitTool("terminal_run",{command:"pwd",network:false},"Run pwd","sidebar"));
        compare(SidebarChat.mode,"chat"); connectAndRun();
        compare(lastRequest().params.tool.name,"terminal_run"); compare(lastRequest().params.tool.arguments.command,"pwd");
        compare(SidebarChat.conversationId,id); finish(); verify(!SidebarChat.active);
    }
    function test_chat_intent_is_preserved() {
        Assistant.submit("how to remove a folder",undefined,"launcher","chat"); connectAndRun();
        compare(lastRequest().params.intent,"chat");
    }
    function test_transaction_history_and_manual_rollback() {
        Assistant.submit("task"); connectAndRun();
        const id=Assistant.submissionId;
        incoming({type:"transaction",transaction_id:id,state:"committed",rollback_available:true,conflicts:[]}); finish();
        compare(SidebarChat.currentReply.transactionState,"committed"); verify(SidebarChat.currentReply.rollbackAvailable);
        verify(ChatStore.saved[SidebarChat.conversationId].messages[1].rollbackAvailable);
        verify(SidebarChat.rollback(SidebarChat.currentReply)); runPending();
        compare(lastRequest().method,"rollback"); compare(lastRequest().params.transaction_id,id);
        replyLast({transaction_id:id,state:"rollback_conflict",rollback_available:true,conflicts:["/changed"]});
        verify(!Assistant.busy); compare(SidebarChat.rollbackRequest,"");
        compare(SidebarChat.currentReply.conflicts[0],"/changed");
    }
    function test_configuration_failure_ends_waiting() {
        Assistant.submit("hello"); incoming({type:"hello",protocol:3});
        incoming({type:"response",id:lastRequest().id,ok:false,error:"configuration failed"});
        compare(Assistant.queued,null); verify(!Assistant.busy); compare(Assistant.problem,"configuration failed");
        compare(SidebarChat.currentReply.status,"error");
    }
    function test_sidebar_infers_action_and_clarification_keeps_intent() {
        SidebarChat.draft="создай папку"; verify(SidebarChat.send()); connectAndRun();
        compare(lastRequest().params.intent,"action"); finish();
        Assistant.submitChoice("target-1","My folder","sidebar"); runPending();
        compare(lastRequest().params.intent,"action");
    }
    function test_native_chat_context_receives_executor_result_without_permissions() {
        Config.options={assistant:{enabled:false,model:"test"},policies:{ai:2}};
        Assistant.submitTool("terminal_run",{command:"pwd"},"Run pwd","sidebar"); connectAndRun();
        incoming({type:"answer",task:Assistant.task,text:"The selected folder is /example"});
        incoming({type:"transaction",transaction_id:Assistant.submissionId,state:"committed",rollback_available:true}); finish();
        SidebarChat.draft="explain the result"; verify(SidebarChat.send());
        verify(Ai.restored.some(m => m.role === "assistant" && m.text.includes("The selected folder is /example")));
        verify(Ai.restored.some(m => m.text.includes("Task status: committed")));
        compare(SidebarChat.currentReply,null); compare(Ai.sent,"explain the result");
    }
    function test_consent_audit_rows_are_not_restored_into_model_context() {
        SidebarChat.append({role:"assistant",text:"Allow sending context?",contextExcluded:true});
        SidebarChat.append({role:"user",text:"actual request"});
        compare(SidebarChat.contextEntries().length,1);
        compare(SidebarChat.contextEntries()[0].text,"actual request");
        SidebarChat.draft="continue"; SidebarChat.send(); incoming({type:"hello",protocol:3}); replyLast();
        compare(lastRequest().method,"restore"); compare(lastRequest().params.messages.length,1);
    }
    function test_legacy_preset_ipc_cannot_mutate_while_busy() {
        Assistant.submit("task"); connectAndRun();
        Presets.presets=[{id:"unsafe",name:"Unsafe"}]; Assistant.lastAppliedPreset="previous";
        compare(Assistant.ipcHandler.applyPreset("unsafe"),"rejected");
        compare(Assistant.lastAppliedPreset,"previous");
        compare(Assistant.ipcHandler.presetStatus("unsafe"),"pending");
        compare(Assistant.ipcHandler.presetStatus("previous"),"applied");
        compare(Assistant.lastAppliedPreset,"previous");
        Presets.presets=[];
    }
    function test_prepared_approvals_show_text_diff_and_sizes() {
        const change={path:"/example/report.txt",change:"modified",before_bytes:4,after_bytes:4,diff:"--- before\n+++ after\n-old\n+new\n"};
        for (const tool of ["terminal_apply","files_copy","files_move","files_zip","files_mkdir","files_trash"]) {
            Assistant.approval={tool,details:{diff:[change]}};
            const description=Assistant.approvalDescription();
            verify(description.includes("-old")); verify(description.includes("+new"));
            verify(description.includes("/example/report.txt")); verify(description.includes("Bytes: 4 → 4"));
            verify(Assistant.approvalReviewComplete);
            if (tool === "files_trash") { verify(description.includes("checkpoint")); verify(!description.includes("trash")); }
        }
        Assistant.approval={tool:"terminal_apply",details:{diff:[{path:"/example/large",change:"modified",diff:"+line\n".repeat(10000),truncated:true}]}};
        verify(Assistant.approvalDescription().length <= 32768);
        verify(Assistant.approvalDescription().includes("truncated"));
        Assistant.approval={tool:"files_copy",details:{diff:[{path:"/example/"+"я".repeat(20000),change:"added"}]}};
        verify(!Assistant.approvalReviewComplete);
        verify(Assistant.approvalDescription().includes("Split this task"));
        Assistant.approval=null;
    }
    function test_history_refreshes_metadata_without_replaying_permissions() {
        const id=SidebarChat.conversationId;
        SidebarChat.append({role:"assistant",text:"Past action",transactionId:"old-task",rollbackAvailable:true});
        SidebarChat.save(); SidebarChat.fresh(); SidebarChat.openConversation(id);
        compare(SidebarChat.messages.length,1); compare(Assistant.approval,null);
        incoming({type:"hello",protocol:3}); replyLast();
        compare(lastRequest().method,"transactions");
        replyLast({transactions:[{transaction_id:"old-task",state:"rolled_back",rollback_available:false,conflicts:[]}]});
        compare(SidebarChat.messages[0].transactionState,"rolled_back");
        verify(!SidebarChat.messages[0].rollbackAvailable); verify(!Assistant.busy);
        verify(!Assistant.backend.writes.some(line => JSON.parse(line).method === "submit"));
    }
}
