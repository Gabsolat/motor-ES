% server.pl : HTTP/JSON glue around kb.pl (pure Prolog, SWI-Prolog 9)
:- use_module(library(http/thread_httpd)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/http_json)).
:- use_module(library(http/http_files)).
:- use_module(library(filesex)).
:- use_module(library(lists)).
:- use_module(library(apply)).
:- ensure_loaded(kb).
:- initialization(main, main).

:- dynamic base_dir/1.
:- prolog_load_context(directory,D), assertz(base_dir(D)).

:- http_handler(root(.),            serve,      [prefix]).
:- http_handler(root('kb.pl'),      serve_src,  []).
:- http_handler(root(api/diagnose), h_diag,     [method(post)]).
:- http_handler(root(api/batch),    h_batch,    [method(post)]).
:- http_handler(root(api/kb),       h_kb,       []).
:- http_handler(root(api/cases),    h_cases,    []).
:- http_handler(root(api/evaluate), h_eval,     []).

serve(Req) :- base_dir(D), directory_file_path(D,static,S),
    http_reply_from_files(S,[indexes(['index.html'])],Req).
serve_src(Req) :- base_dir(D), directory_file_path(D,'kb.pl',F),
    http_reply_file(F,[mime_type(text/plain)],Req).

to_atom(S,A) :- atom_string(A,S).
to_num(V0,V) :- number(V0), !, V = V0.
to_num(V0,V) :- string(V0), catch(number_string(V,V0),_,fail).
obs_of(Dict,Obs) :- dict_pairs(Dict,_,Ps),
    findall(K-V,(member(K-V0,Ps),to_num(V0,V)),Obs).
req_cfg(D,Mode,Scale,Off) :-
    ( get_dict(mode,D,M0) -> atom_string(Mode,M0) ; Mode = full ),
    ( get_dict(scale,D,S0), number(S0) -> Scale = S0 ; Scale = 1.0 ),
    ( get_dict(disable,D,L0) -> maplist(to_atom,L0,Off) ; Off = [] ).

h_diag(Req) :- http_read_json_dict(Req,D), req_cfg(D,Mode,Scale,Off),
    ( get_dict(obs,D,O) -> true ; O = _{} ), obs_of(O,Obs),
    diag_dict(Mode,Scale,Off,Obs,Out), reply_json_dict(Out).
h_batch(Req) :- http_read_json_dict(Req,D), req_cfg(D,Mode,Scale,Off),
    get_dict(rows,D,Rows),
    findall(Out,(member(R,Rows),obs_of(R,Obs),diag_dict(Mode,Scale,Off,Obs,Out)),Outs),
    reply_json_dict(_{results:Outs}).
h_kb(_) :-
    findall(_{key:K,limit:L,type:T,source:Src},(th(K,L,P),P =.. [T,Src]),Th),
    findall(_{id:F,code:C,name:N,component:Cp,group:G},fault(F,C,N,Cp,G),Fs),
    findall(_{fault:F,symptom:S,label:L,weight:W},(sig(F,S,W),symptom(S,L)),Sg),
    findall(_{fault:F,action:A,priority:P,verify:V},maint(F,A,P,V),Mt),
    reply_json_dict(_{thresholds:Th,faults:Fs,signatures:Sg,maintenance:Mt}).
h_cases(_) :-
    findall(_{id:I,test:T,truth:Tr,obs:O},
        (case(I,T,Tr,Dl),case_obs(Dl,Ob),dict_create(O,_,Ob)),Cs),
    reply_json_dict(_{cases:Cs}).
h_eval(_) :- evaluate(Out), reply_json_dict(Out).

% ---------- explanation facility ----------------------------------------
explain(F,_{fault:F,code:C,name:N,confidence:Cf,evidence:Ev,rules:Rules,missing:Ms,
            action:A,priority:P,verify:V}) :-
    fault(F,C,N,_,_), pconf(F,Cf), maint(F,A,P,V),
    findall(_{symptom:S,label:L,weight:W},(sig(F,S,W),sym(S),symptom(S,L)),Ev),
    findall(Id,(sig(F,S,_),sym(S),format(atom(Id),'R.~w.~w',[C,S])),Rules),
    findall(L,(sig(F,S,_),\+ sym(S),symptom(S,L)),Ms).
reject_reason(F,C,R) :-
    (   \+ enabled(F) -> R = 'knowledge group disabled'
    ;   \+ ( sig(F,S,3), sym(S) ) -> R = 'no core indicator observed'
    ;   cfg(dthr,D), C < D -> R = 'confidence below deductive threshold'
    ;   R = 'removed by consistency-based minimal diagnoses' ).

diag_dict(Mode,Scale,Off,Obs,Out) :-
    setup_ctx(Obs,Scale,Off),
    get_time(T0), diagnose(Mode,Final,info(Ss,Ded,Ranked,Ambig,Cbd)), get_time(T1),
    Ms is (T1-T0)*1000,
    findall(E,(member(F,Final),explain(F,E)),Exs),
    findall(_{symptom:S,label:L},(member(S,Ss),symptom(S,L)),Syms),
    findall(_{symptom:S,label:L,reason:R},
        (raw(S),exc(S),symptom(S,L),exc_reason(S,R)),Def),
    findall(_{fault:F,code:C,conf:Cf,deductive:Dd},
        (fault(F,C,_,_,_),F \== normal,pconf(F,Cf),
         ( memberchk(F-_,Ded) -> Dd = true ; Dd = false )),Scores),
    findall(_{faults:H,score:Sc},member(Sc-H,Ranked),Abd),
    findall(_{fault:F,confidence:C,reason:R},
        (fault(F,_,_,_,_),F \== normal,\+ memberchk(F,Final),pconf(F,C),C > 0,
         reject_reason(F,C,R)),Rej),
    regime(Rg),
    ( slip_dev(SD) -> true ; SD = null ),
    ( p_resid(PR) -> true ; PR = null ),
    ( Final == [normal] -> St = normal
    ; Final == [] -> ( Ss == [] -> St = undetermined ; Ambig == true -> St = ambiguous ; St = undetermined )
    ; St = diagnosed ),
    Out = _{status:St,mode:Mode,final:Final,explanations:Exs,symptoms:Syms,defeated:Def,
            scores:Scores,abductive:Abd,cbd:Cbd,rejected:Rej,time_ms:Ms,
            derived:_{regime:Rg,slip_dev:SD,p_resid:PR}}.

main :-
    ( getenv('PORT',P0), atom_number(P0,Port) -> true ; Port = 8080 ),
    http_server(http_dispatch,[port(Port)]),
    format("Motor-drive expert system on port ~w~n",[Port]),
    thread_get_message(_).
