import QtQuick
import QtTest
import "."

TestCase {
    name: "Lens"
    function init() {
        Config.options = ({search:{lens:{enabled:true}}});
        GlobalStates.screenLocked = false;
        Lens.mainShell = false;
        Lens.ready = true;
        Lens.status = ({locked:false, config:{source_reviews:[]}});
        Lens.reviewingSource = "";
        Lens.results = [];
        Lens.query = "";
        Lens.pending = ({});
        Lens.process.writes = [];
        Lens.semanticTimer.stop();
        Lens.setupInfo = ({ installed: true, models: false, running: false, stage: "" });
        Lens.setupActionProcess.running = false;
        Lens.setupStatusProcess.running = false;
        TestLauncher.urls = [];
        TestLauncher.apps = [];
        Quickshell.commands = [];
        AppSearch.list = [];
    }
    function lastRequest() { return JSON.parse(Lens.process.writes[Lens.process.writes.length - 1]); }
    function respond(id, results) { Lens.handle(JSON.stringify({type:"response", id, ok:true, result:{results}})); }
    function resolve(request, result) { Lens.handle(JSON.stringify({type:"response", id:request.id, ok:true, result})); }
    function openCurrent(hit, parent) { Lens.results=[hit]; Lens.open(hit,parent); }
    function test_semantic_search_requires_explicit_opt_in() {
        Lens.search("a description of a document");
        compare(lastRequest().method, "search");
        verify(!lastRequest().params.semantic);
        verify(!Lens.semanticTimer.running);
        Lens.status = ({locked:false, config:{semantic:true}});
        Lens.search("a description of a document");
        verify(Lens.semanticTimer.running);
        Lens.cancelSearch();
    }
    function test_disabling_search_cancels_requests_and_discards_late_results() {
        Lens.status = ({locked:false, config:{semantic:true}});
        Lens.search("private document");
        const id = lastRequest().id;
        Config.options = ({search:{lens:{enabled:false}}});
        verify(!Lens.enabled);
        verify(!Lens.process.running);
        verify(!Lens.semanticTimer.running);
        respond(id, [{id:1, name:"late result"}]);
        compare(Lens.results.length, 0);
        Lens.search("another query");
        compare(lastRequest().method, "cancel");
        verify(!Lens.semanticTimer.running);
    }
    function test_old_result_cannot_open_after_query_change() {
        const hit={id:100,path:"/old"};Lens.results=[hit];Lens.search("new");
        const before=Lens.process.writes.length;Lens.open(hit,false);compare(Lens.process.writes.length,before);
    }
    function test_open_uses_resolved_path_and_encodes_spaces_unicode_and_fragments() {
        openCurrent({id:42,path:"/outdated/name.txt"}, false);
        const request=lastRequest(); compare(request.method,"resolve"); compare(request.params.id,42);
        Lens.search("different query"); Lens.semanticTimer.stop();
        resolve(request,{kind:"file",path:"/home/example/NLP/домашка #1 %.ipynb"});
        compare(TestLauncher.urls.length,1);
        compare(TestLauncher.urls[0],"file:///home/example/NLP/"+encodeURIComponent("домашка #1 %.ipynb"));
        compare(lastRequest().method,"record");
        compare(lastRequest().params.path,"/home/example/NLP/домашка #1 %.ipynb");
    }
    function test_open_folder_and_show_parent_use_the_selected_location() {
        openCurrent({id:5},false);resolve(lastRequest(),{kind:"folder",path:"/home/example/NLP"});
        compare(TestLauncher.urls[0],"file:///home/example/NLP");
        openCurrent({id:6},true);resolve(lastRequest(),{kind:"file",path:"/home/example/NLP/homework.ipynb"});
        compare(TestLauncher.urls[1],"file:///home/example/NLP");
    }
    function test_application_activation_uses_desktop_entry() {
        AppSearch.list=[{id:"example.desktop",execute:()=>TestLauncher.apps=TestLauncher.apps.concat(["example"])}];
        openCurrent({id:7},false);resolve(lastRequest(),{kind:"app",path:"app:example.desktop"});
        compare(TestLauncher.apps.length,1);compare(TestLauncher.apps[0],"example");
        compare(TestLauncher.urls.length,0);
    }
    function test_video_activation_passes_path_as_argument_and_keeps_frame_position() {
        openCurrent({id:8,timestamp:12.5},false);resolve(lastRequest(),{kind:"video",path:"/home/example/video ; name.mp4"});
        compare(Quickshell.commands.length,1);
        compare(JSON.stringify(Quickshell.commands[0]),JSON.stringify(["mpv","--start=12.5","--","/home/example/video ; name.mp4"]));
    }
    function test_failed_resolve_and_lock_prevent_activation() {
        openCurrent({id:9},false);const request=lastRequest();
        Lens.handle(JSON.stringify({type:"response",id:request.id,ok:false,error:{message:"File no longer exists"}}));
        compare(TestLauncher.urls.length,0);
        openCurrent({id:10},false);const locked=lastRequest();GlobalStates.screenLocked=true;
        resolve(locked,{kind:"file",path:"/home/example/private.pdf"});
        compare(TestLauncher.urls.length,0);
    }
    function test_stale_response_never_replaces_current_results() {
        Lens.search("old"); const old = lastRequest().id;
        Lens.search("new"); const current = lastRequest().id;
        respond(current, [{name:"new result"}]);
        respond(old, [{name:"stale private result"}]);
        compare(Lens.results.length, 1);
        compare(Lens.results[0].name, "new result");
        Lens.semanticTimer.stop();
    }
    function test_query_waits_for_opening_then_resumes_without_more_typing() {
        Lens.status = ({locked:true, opening:true});
        Lens.search("saved query");
        compare(lastRequest().method, "cancel");
        verify(!Lens.semanticTimer.running);
        Lens.refresh();
        resolve(lastRequest(), {locked:false, opening:false, config:{semantic:false}});
        compare(lastRequest().method, "search");
        compare(lastRequest().params.query, "saved query");
        respond(lastRequest().id, [{name:"ready result"}]);
        compare(Lens.results[0].name, "ready result");
    }
    function test_lock_during_opening_never_resumes_the_old_query() {
        Lens.mainShell = true;
        Lens.status = ({locked:true, opening:true});
        Lens.search("private query");
        GlobalStates.screenLocked = true;
        const locked = lastRequest();
        Lens.acceptStatus({locked:false, opening:false});
        compare(lastRequest().id, locked.id);
        compare(Lens.query, "");
        compare(Lens.results.length, 0);
    }
    function test_explicit_file_intent_is_available_for_launcher_priority() {
        Lens.search("config for keyboard hypr");
        const id = lastRequest().id;
        Lens.handle(JSON.stringify({type:"response", id, ok:true, result:{query:{kind:"config"}, results:[{name:"general.lua"}]}}));
        compare(Lens.queryKind, "config");
        Lens.search("firefox");
        compare(Lens.queryKind, "");
        Lens.semanticTimer.stop();
    }
    function test_short_identifier_response_stops_semantic_request() {
        Lens.status = ({locked:false, config:{semantic:true}});
        Lens.search("npl");
        verify(Lens.semanticTimer.running);
        const id = lastRequest().id;
        Lens.handle(JSON.stringify({type:"response", id, ok:true, result:{query:{kind:null}, semantic_recommended:false, results:[]}}));
        verify(!Lens.semanticTimer.running);
        compare(Lens.results.length, 0);
    }
    function test_fuzzy_and_partial_results_explain_their_evidence() {
        const corrected = Lens.explanation({reason:"project",corrections:[{from:"hupr",to:"hypr"}],partial:false});
        verify(corrected.includes("Matching files in this folder"));
        verify(corrected.includes("hupr → hypr"));
        const partial = Lens.explanation({reason:"content",partial:true,unmatched_terms:["missingfeature"]});
        verify(partial.includes("Partial match"));
        verify(partial.includes("missingfeature"));
        const content = Lens.explanation({reason:"content",snippet:"First homework\n  about language"});
        verify(content.includes("First homework about language"));
        verify(Lens.explanation({reason:"content",snippet:"x".repeat(1000)}).length < 300);
        compare(Lens.explanation({reason:"name"}),"Name match");
    }
    function test_large_folder_choice_waits_for_acknowledgement_and_can_retry_errors() {
        const path = "/home/example/Projects/llvm-project";
        Lens.status = ({locked:false, config:{source_reviews:[{path, files:10000}]}});
        Lens.reviewSource(path, true);
        const request = lastRequest();
        compare(request.method, "review_source");
        compare(request.params.path, path);
        verify(request.params.include);
        compare(Lens.status.config.source_reviews.length, 1);
        compare(Lens.reviewingSource, path);
        Lens.reviewSource(path, false);
        compare(lastRequest().id, request.id);
        Lens.handle(JSON.stringify({type:"response", id:request.id, ok:false, error:{message:"Try again"}}));
        compare(Lens.reviewingSource, "");
        compare(Lens.status.config.source_reviews.length, 1);
        Lens.reviewSource(path, false);
        const retry = lastRequest();
        verify(!retry.params.include);
        Lens.handle(JSON.stringify({type:"response", id:retry.id, ok:true, result:{locked:false, config:{source_reviews:[],excludes:[path]}}}));
        compare(Lens.status.config.source_reviews.length, 0);
        compare(Lens.status.config.excludes[0], path);
        compare(Lens.reviewingSource, "");
    }
    function test_lock_clears_private_results_and_invalidates_inflight_query() {
        Lens.mainShell = true;
        Lens.search("private"); const id = lastRequest().id;
        Lens.results = [{name:"private document"}];
        GlobalStates.screenLocked = true;
        compare(Lens.results.length, 0);
        compare(lastRequest().method, "context");
        verify(lastRequest().params.locked);
        respond(id, [{name:"late private document"}]);
        compare(Lens.results.length, 0);
        Lens.semanticTimer.stop();
    }
    function test_empty_query_cancels_work() {
        Lens.search("project"); Lens.search("");
        compare(lastRequest().method, "cancel");
        compare(Lens.results.length, 0);
        verify(!Lens.semanticTimer.running);
    }
    function test_protocol_mismatch_is_not_accepted() {
        Lens.ready = false;
        Lens.handle('{"type":"hello","protocol":99}');
        verify(!Lens.ready);
        verify(!Lens.process.running);
    }
    function test_missing_binary_is_not_presented_as_a_keyring_error() {
        Lens.handle('{"type":"unavailable","code":"not_installed"}');
        Lens.process.exited(127, 0);
        compare(Lens.setupInfo.installed, false);
        compare(Lens.problem, "");
        verify(!Lens.ready);
    }
    function test_setup_runs_in_settings_without_a_terminal() {
        Lens.setupInfo = ({running:false, stage:"failed", progress:{unit:"bytes", done:100, total:100}, steps_done:4, elapsed_seconds:999});
        Lens.prepare();
        verify(Lens.setupRunning);
        compare(Lens.setupInfo.steps_done, 0);
        compare(Lens.setupInfo.elapsed_seconds, 0);
        compare(Object.keys(Lens.setupInfo.progress).length, 0);
        compare(Lens.setupActionProcess.command[1], "setup-start");
        compare(Lens.setupActionProcess.command[2], "models");
        verify(Lens.setupActionProcess.running);
        Lens.setupActionProcess.running = false;
        Lens.cancelSetup();
        compare(Lens.setupActionProcess.command[1], "setup-cancel");
    }
    function test_setup_label_distinguishes_download_export_and_failure() {
        Lens.setupInfo = ({running:true, stage:"models", progress:{task:"model-download", model:"e5"}});
        compare(Lens.setupLabel(), "Downloading the text model");
        Lens.setupInfo = ({running:true, stage:"models", progress:{task:"model-export", model:"siglip"}});
        compare(Lens.setupLabel(), "Preparing the image model");
        Lens.setupInfo = ({running:false, stage:"failed", progress:{task:"model-export", model:"siglip"}});
        compare(Lens.setupLabel(), "Setup could not finish");
    }
}
