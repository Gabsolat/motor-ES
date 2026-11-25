% =====================================================================
% kb.pl : Knowledge base + reasoning core for industrial motor-drive
% fault diagnosis. Strict Prolog (SWI-Prolog 9). No external logic.
% Provenance tags: l(Source) literature-supported, a(Note) engineering
% assumption. All test cases are SYNTHETIC (see case/4).
% =====================================================================
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(aggregate)).
:- use_module(library(pairs)).

:- thread_local obs/2, scale/1, off/1.

% ---------- thresholds th(Key, Limit, Provenance) ------------------
th(vunb,        1.0, l('NEMA MG1-14.36; IEC 60034-26 (voltage unbalance, %)')).
th(iunb,       10.0, a('current unbalance alarm, nominal load')).
th(iunb_low,   20.0, a('light-load exception to iunb')).
th(sb_margin,  45.0, l('Thomson and Fenger 2001: rotor sideband margin below fundamental, dB')).
th(ecc_margin, 45.0, a('eccentricity sideband margin, dB')).
th(vib,         4.5, l('ISO 20816-3 zone C/D boundary, rigid support (mm/s RMS)')).
th(bpfo_snr,    6.0, a('envelope-spectrum SNR at BPFO, dB')).
th(vib1x,       0.6, a('1X share of overall vibration')).
th(vib2x,       0.4, a('2X share of overall vibration')).
th(tb,         85.0, a('bearing housing temperature alarm, C')).
th(tw,        140.0, l('IEC 60034-1 class F limit 155 C less margin')).
th(cool_flow,  80.0, a('coolant/air flow, % of nominal')).
th(rins,        5.0, l('IEEE 43-2013 minimum insulation resistance, random-wound LV (MOhm)')).
th(pi,          2.0, l('IEEE 43-2013 minimum polarization index, class F')).
th(pf,         0.75, a('power factor floor, nominal/high load')).
th(pf_low,      0.5, a('power factor floor, light-load exception')).
th(slip_dev,    0.5, a('relative slip deviation from load-expected slip')).
th(thdi,        8.0, l('IEEE 519-2022 TDD limit 8 % for 20<Isc/IL<50')).
th(vdc_ripple,  5.0, a('DC-link ripple, %')).
th(tj,        125.0, l('IGBT datasheets: Tj,max 150 C derated')).
th(vout_unb,    3.0, a('inverter output voltage unbalance, %')).
th(torque_ripple,10.0, a('torque ripple, %')).
th(us_db,       8.0, a('ultrasound rise over baseline, dB (lubrication)')).
th(p_resid,    0.15, a('power-balance residual, eq. 31')).
th(rtd_diff,   10.0, a('redundant RTD disagreement, K')).

cfg(dthr, 0.4).   % deductive confidence threshold
cfg(athr, 0.5).   % abductive acceptance threshold

thr(K,L) :- th(K,L0,_), ( scale(S) -> true ; S = 1.0 ), L is L0*S.
gt(K) :- obs(K,V), thr(K,L), V > L.
lt(K) :- obs(K,V), thr(K,L), V < L.

% ---------- operating regime (default / exception context) -----------
regime(R) :- ( obs(load,L) -> ( L < 40 -> R = low ; L > 100 -> R = high ; R = nominal ) ; R = nominal ).

% ---------- engineering calculations ---------------------------------
slip_dev(D) :- obs(slip,S), obs(load,Ld), Ld >= 20,
    ( obs(srated,Sr) -> true ; Sr = 2.0 ), E is Sr*Ld/100, D is (S-E)/E.
p_resid(R) :- obs(vll,V), obs(i,I), obs(pf,PF), obs(p_kw,P),
    Pc is sqrt(3)*V*I*PF/1000, Pc > 0, R is abs(P-Pc)/Pc.

% ---------- symptom definitions symptom(Id, Label) -------------------
symptom(vunb_high,'Supply voltage unbalance above limit').
symptom(iunb_high,'Stator current unbalance above regime limit').
symptom(sb_high,'Rotor-bar sidebands above limit').
symptom(ecc_high,'Eccentricity sidebands above limit').
symptom(vib_high,'Overall vibration above ISO zone limit').
symptom(bpfo_high,'Bearing defect frequency visible in envelope spectrum').
symptom(vib_sync_high,'Dominant 1X or 2X vibration').
symptom(tb_high,'Bearing temperature high').
symptom(tw_high,'Winding temperature high').
symptom(cool_low,'Cooling flow degraded').
symptom(rins_low,'Insulation resistance low').
symptom(pi_low,'Polarization index low').
symptom(pf_low,'Power factor low for regime').
symptom(slip_high,'Slip above load-expected value').
symptom(thdi_high,'Current THD high').
symptom(ripple_high,'DC-link ripple high').
symptom(tj_high,'Junction temperature high').
symptom(vout_unb_high,'Inverter output voltage unbalanced').
symptom(torque_ripple_high,'Torque ripple high').
symptom(us_high,'Ultrasound level raised').
symptom(p_resid_high,'Measured power inconsistent with V, I, PF').
symptom(rtd_diff_high,'Redundant temperature sensors disagree').

% raw symptom: threshold exceeded
raw(vunb_high) :- gt(vunb).
raw(iunb_high) :- regime(R), ( R == low -> K = iunb_low ; K = iunb ),
    obs(iunb,V), thr(K,L), V > L.
raw(sb_high) :- lt(sb_margin).
raw(ecc_high) :- lt(ecc_margin).
raw(vib_high) :- gt(vib).
raw(bpfo_high) :- gt(bpfo_snr).
raw(vib_sync_high) :- ( gt(vib1x) -> true ; gt(vib2x) ).
raw(tb_high) :- gt(tb).
raw(tw_high) :- gt(tw).
raw(cool_low) :- lt(cool_flow).
raw(rins_low) :- lt(rins).
raw(pi_low) :- lt(pi).
raw(pf_low) :- regime(R), ( R == low -> K = pf_low ; K = pf ),
    obs(pf,V), thr(K,L), V < L.
raw(slip_high) :- slip_dev(D), thr(slip_dev,L), D > L.
raw(thdi_high) :- gt(thdi).
raw(ripple_high) :- gt(vdc_ripple).
raw(tj_high) :- gt(tj).
raw(vout_unb_high) :- gt(vout_unb).
raw(torque_ripple_high) :- gt(torque_ripple).
raw(us_high) :- gt(us_db).
raw(p_resid_high) :- p_resid(R), thr(p_resid,L), R > L.
raw(rtd_diff_high) :- gt(rtd_diff).

% ---------- defaults and exceptions (defeasible symptoms) -------------
exc(iunb_high) :- ( raw(vunb_high) ; raw(vout_unb_high) ), !.
exc(tw_high)   :- raw(rtd_diff_high).
exc(pf_low)    :- raw(p_resid_high).
exc(sb_high)   :- regime(low).
exc_reason(iunb_high,'explained by supply or inverter-output voltage unbalance').
exc_reason(tw_high,'winding RTD readings disagree: measurement quarantined').
exc_reason(pf_low,'power measurement inconsistent: measurement quarantined').
exc_reason(sb_high,'sideband diagnosis unreliable below 40 % load').

ctx(vunb_high).                       % context only, not a motor fault symptom
sym(S) :- raw(S), \+ exc(S).
abn(S) :- sym(S), \+ ctx(S).

% ---------- fault taxonomy fault(Id, Code, Name, Component, Group) ----
fault(f_stator,  'FSB','Stator-winding fault',          stator,          electrical).
fault(f_rotor,   'FSR','Rotor fault (broken bars)',     rotor,           electrical).
fault(f_bearing, 'FBR','Bearing fault',                 bearing,         mechanical).
fault(f_lube,    'FBB','Bearing lubrication fault',     lubrication,     mechanical).
fault(f_insul,   'FMI','Motor insulation fault',        insulation,      electrical).
fault(f_unbal,   'FUM','Unbalance / misalignment',      alignment,       mechanical).
fault(f_vfd,     'FVFD','VFD / power-electronic fault', vfd_power,       drive).
fault(f_igbt,    'FIG','Inverter gating abnormality',   inverter_gating, drive).
fault(f_thermal, 'FTH','Thermal / cooling fault',       cooling,         thermal).
fault(f_coupling,'FCO','Coupling / load fault',         load_coupling,   mechanical).
fault(f_eccent,  'FME','Mechanical eccentricity',       air_gap,         mechanical).
fault(f_sensor,  'FI', 'Instrumentation / control fault',sensing,        sensing).
fault(normal,    'FN', 'Normal operation',              none,            none).

% ---------- fault signatures sig(Fault, Symptom, Weight 1..3) ---------
% weight 3 = core indicator (causal, discriminating)
sig(f_stator, iunb_high,3).  sig(f_stator, tw_high,2).   sig(f_stator, pf_low,1).
sig(f_rotor,  sb_high,3).    sig(f_rotor, slip_high,2).  sig(f_rotor, vib_high,1).
sig(f_rotor,  torque_ripple_high,1).
sig(f_bearing,bpfo_high,3).  sig(f_bearing,vib_high,2).  sig(f_bearing,tb_high,2).
sig(f_bearing,us_high,1).
sig(f_lube,   us_high,3).    sig(f_lube,tb_high,2).      sig(f_lube,vib_high,1).
sig(f_insul,  rins_low,3).   sig(f_insul,pi_low,2).      sig(f_insul,tw_high,1).
sig(f_unbal,  vib_sync_high,3). sig(f_unbal,vib_high,2).
sig(f_vfd,    ripple_high,3).sig(f_vfd,thdi_high,2).     sig(f_vfd,torque_ripple_high,1).
sig(f_igbt,   vout_unb_high,3). sig(f_igbt,tj_high,2).   sig(f_igbt,iunb_high,1).
sig(f_thermal,cool_low,3).   sig(f_thermal,tw_high,2).   sig(f_thermal,tb_high,1).
sig(f_coupling,torque_ripple_high,3). sig(f_coupling,vib_sync_high,1). sig(f_coupling,slip_high,1).
sig(f_eccent, ecc_high,3).   sig(f_eccent,vib_high,1).
sig(f_sensor, p_resid_high,3). sig(f_sensor,rtd_diff_high,3).

% ---------- maintenance rules maint(Fault, Action, Priority, Verify) --
maint(f_stator,'Isolate and lock out; measure winding resistance balance, insulation resistance and surge-test; rewind or replace stator if turn-to-turn short is confirmed.',high,'Re-measure current unbalance and winding resistance; trend winding temperature over 2 h at load.').
maint(f_rotor,'Perform loaded MCSA retest and inspect rotor bars/end rings; repair or replace rotor if cracks are confirmed.',high,'Repeat sideband measurement at above 50 % load; compare with baseline.').
maint(f_bearing,'Replace bearing, inspect shaft and housing fits, verify lubricant type and quantity.',high,'Envelope spectrum at BPFO and bearing temperature after 24 h run.').
maint(f_lube,'Inspect lubricant condition and grease quantity/interval; relubricate per OEM procedure; check seals.',medium,'Ultrasound level and bearing temperature after relubrication.').
maint(f_insul,'Perform IEEE 43 insulation resistance and PI test; clean and dry winding; rewind or varnish-treat if still below limit.',high,'Re-run IR and PI tests; confirm values above IEEE 43 minimum.').
maint(f_unbal,'Perform laser shaft alignment and field balancing; check soft foot and coupling condition.',medium,'Vibration spectrum 1X and 2X share and overall level after correction.').
maint(f_vfd,'Inspect DC-link capacitors and input chokes; check line harmonics and cooling of the drive.',medium,'Measure DC ripple and current THD at same load.').
maint(f_igbt,'Check gate-driver signals and IGBT modules; replace faulty module; verify deadtime and DC-link balance.',high,'Measure output voltage balance and junction temperature at rated load.').
maint(f_thermal,'Clean fan, filters and cooling passages; verify coolant flow and ambient conditions.',medium,'Coolant flow and winding temperature at rated load.').
maint(f_coupling,'Inspect coupling elements and driven-load condition; correct looseness or load oscillation.',medium,'Torque ripple and slip against load after correction.').
maint(f_eccent,'Measure air gap and bearing wear; correct end-shield fit or replace bearings.',medium,'Eccentricity sideband margin and vibration after correction.').
maint(f_sensor,'Verify and recalibrate the suspect sensors against a calibrated reference; do not act on quarantined readings.',low,'Redundant sensors agree and power balance residual below limit.').
maint(normal,'Continue routine condition monitoring.',low,'Next scheduled data capture.').

% ---------- helper logic ---------------------------------------------
enabled(F) :- fault(F,_,_,_,G), F \== normal, \+ off(G).
sum_w([],0).
sum_w([_-W|T],S) :- sum_w(T,S0), S is S0+W.
pconf(normal,1.0) :- !.
pconf(F,C) :- findall(S-W,sig(F,S,W),A), sum_w(A,T),
    findall(S-W,(sig(F,S,W),sym(S)),E), sum_w(E,Es), C is Es/T.

% ---------- deductive diagnosis:  KB u E |= F -------------------------
ded(F,C,Ev) :- enabled(F),
    findall(S-W,(sig(F,S,W),sym(S)),Ev), memberchk(_-3,Ev),
    pconf(F,C), cfg(dthr,D), C >= D.

% ---------- abductive diagnosis: D u KB |= E (min-cardinality covers) -
comb(0,_,[]) :- !.
comb(N,[X|T],[X|R]) :- N1 is N-1, comb(N1,T,R).
comb(N,[_|T],R) :- N > 0, comb(N,T,R).
covers(H,Un) :- forall(member(S,Un),(member(F,H),sig(F,S,_))).
abduce(Un,Covers) :-
    findall(F,(member(S,Un),sig(F,S,_),enabled(F)),L0), sort(L0,Cs),
    between(1,3,N), findall(H,(comb(N,Cs,H),covers(H,Un)),Covers), Covers \== [], !.
abduce(_,[]).
cover_score(H,Sc) :- findall(C,(member(F,H),pconf(F,C)),Cs), sum_list(Cs,Sc).
best_cover([],[],false).
best_cover([_-H],B,Amb) :- !, accept_cover(H,B,Amb).
best_cover([S1-H,S2-_|_],B,Amb) :-
    ( S1 > S2 -> accept_cover(H,B,Amb) ; B = [], Amb = true ).
accept_cover(H,B,Amb) :- cfg(athr,A),
    ( forall(member(F,H),(pconf(F,C),C >= A)) -> B = H, Amb = false ; B = [], Amb = true ).

% ---------- consistency-based diagnosis (Reiter: minimal hitting sets)
hits(D,Confl) :- forall(member(Cf,Confl),(member(C,D),memberchk(C,Cf))).
minimal(Ds,Min) :- findall(D,(member(D,Ds),\+ (member(E,Ds),E \== D,subset(E,D))),Min).
cbd([],[],[]) :- !.
cbd(Ss,Diags,Faults) :-
    findall(Cs,(member(S,Ss),
                findall(C,(sig(F,S,_),enabled(F),fault(F,_,_,C,_)),L),
                sort(L,Cs), Cs \== []),Confl),
    ( Confl == [] -> Diags = [], Faults = []
    ; append(Confl,A0), sort(A0,All),
      findall(D,(between(1,3,N),comb(N,All,D),hits(D,Confl)),Ds0),
      minimal(Ds0,Diags), append(Diags,DC0), sort(DC0,DC),
      findall(F,(member(C,DC),fault(F,_,_,C,_)),Faults) ).

% ---------- diagnosis driver ------------------------------------------
% Mode: ded | ded_abd | ded_cbd | full
member_of(L,X) :- memberchk(X,L).
rank_faults(Fs,Ranked) :-
    findall(C-F,(member(F,Fs),pconf(F,C)),P0), sort(0,@>=,P0,P), pairs_values(P,Ranked).
diagnose(Mode,Final,info(Ss,Ded,Ranked,Ambig,Cbd)) :-
    findall(S,abn(S),Ss0), sort(Ss0,Ss),
    findall(F-C,ded(F,C,_),Ded), pairs_keys(Ded,DF),
    findall(S,(member(F,DF),sig(F,S,_),memberchk(S,Ss)),E0), sort(E0,Ex),
    subtract(Ss,Ex,Un),
    ( Un == [] -> Ranked = [] ; abduce(Un,Cov),
      findall(Sc-H,(member(H,Cov),cover_score(H,Sc)),R0), sort(0,@>=,R0,Ranked) ),
    best_cover(Ranked,Best,Ambig),
    cbd(Ss,Cbd,CbdF),
    ( memberchk(Mode,[ded_abd,full]) -> Add = Best ; Add = [] ),
    union(DF,Add,Base),
    ( memberchk(Mode,[ded_cbd,full]) -> include(member_of(CbdF),Base,Kept) ; Kept = Base ),
    ( Ss == [] -> Final0 = [normal] ; Final0 = Kept ),
    rank_faults(Final0,Final).

% ---------- synthetic test cases (NOT measured data) -------------------
base([vll-400,i-50,pf-0.86,p_kw-29.8,load-75,vunb-0.4,iunb-3,sb_margin-58,
      ecc_margin-60,vib-2.1,bpfo_snr-2,vib1x-0.3,vib2x-0.15,tb-62,tw-105,
      cool_flow-100,rins-800,pi-3.5,slip-1.6,srated-2.0,thdi-4,vdc_ripple-2,
      tj-85,vout_unb-1,torque_ripple-4,us_db-2,rtd_diff-2]).

case(a1,'A',[normal],[]).
case(a2,'A',[normal],[load-30,i-25,pf-0.6,p_kw-10.4,iunb-12,slip-0.6]).
case(a3,'A',[normal],[load-110,i-62,pf-0.88,p_kw-37.8,slip-2.2]).
case(b1,'B',[f_stator],[iunb-16,tw-150]).
case(b2,'B',[f_rotor],[sb_margin-38,slip-2.6]).
case(b3,'B',[f_insul],[rins-1.5,pi-1.4]).
case(c1,'C',[f_bearing],[bpfo_snr-14,vib-6.2,tb-92]).
case(c2,'C',[f_lube],[us_db-14,tb-90]).
case(c3,'C',[f_unbal],[vib1x-0.75,vib-5.2]).
case(c4,'C',[f_eccent],[ecc_margin-38,vib-4.9]).
case(d1,'D',[f_vfd],[vdc_ripple-9,thdi-11]).
case(d2,'D',[f_igbt],[vout_unb-6,tj-135,iunb-14]).
case(d3,'D',[f_thermal],[cool_flow-55,tw-148]).
case(d4,'D',[f_coupling],[torque_ripple-18,slip-2.5]).
case(e1,'E',[f_bearing,f_unbal],[bpfo_snr-12,vib-7,tb-90,vib1x-0.7]).
case(e2,'E',[f_stator,f_thermal],[iunb-15,tw-155,cool_flow-60]).
case(e3,'E',[f_rotor,f_bearing],[sb_margin-40,slip-2.7,bpfo_snr-10,vib-5.5,tb-88]).
case(f1,'F',[f_bearing],[vib-6.0]).
case(f2,'F',[f_lube],[tb-88]).
case(g1,'G',[f_bearing],[bpfo_snr-12,tb-90,vib-none]).
case(g2,'G',[f_rotor],[sb_margin-44,slip-2.3]).
case(g3,'G',[f_sensor],[tw-150,rtd_diff-18]).
case(g4,'G',[f_sensor],[p_kw-19]).
case(g5,'G',[normal],[vunb-3.5,iunb-14]).
case(g6,'G',[f_insul],[rins-none,pi-1.5,tw-146]).

apply_delta(K-V,O0,O) :-
    ( selectchk(K-_,O0,O1) -> true ; O1 = O0 ),
    ( V == none -> O = O1 ; O = [K-V|O1] ).
case_obs(Deltas,Obs) :- base(B), foldl(apply_delta,Deltas,B,Obs).
setup_ctx(Obs,Scale,Off) :-
    retractall(obs(_,_)), retractall(scale(_)), retractall(off(_)),
    forall(member(K-V,Obs),assertz(obs(K,V))), assertz(scale(Scale)),
    forall(member(G,Off),assertz(off(G))).

% ---------- evaluation (metrics defined in report section 4) ----------
traced(normal).
traced(F) :- F \== normal, findall(S,(sig(F,S,_),sym(S)),[_|_]).
plan_ok(F) :- maint(F,A,P,V), A \== '', V \== '', memberchk(P,[high,medium,low]), traced(F).

run_case(Mode,Scale,Off,case(Id,T,Truth,Dl),r(Id,T,Truth,Final,Ms,Ex,Pv)) :-
    case_obs(Dl,Obs), setup_ctx(Obs,Scale,Off),
    get_time(T0), diagnose(Mode,Final,_), get_time(T1), Ms is (T1-T0)*1000,
    ( Final == [] -> Ex = none, Pv = none
    ; ( forall(member(F,Final),traced(F)) -> Ex = 1 ; Ex = 0 ),
      ( forall(member(F,Final),plan_ok(F)) -> Pv = 1 ; Pv = 0 ) ).

exact(T,F) :- sort(T,S), sort(F,S).
sd(_,B,null) :- B =:= 0, !.
sd(A,B,V) :- V is A/B.
f1v(P,R,F) :- ( number(P), number(R), P+R > 0 -> F is 2*P*R/(P+R) ; F = null ).
nz(null,0) :- !.
nz(X,X).
ratio_of(Rs,Pos,V) :-
    findall(X,(member(R,Rs),arg(Pos,R,X),number(X)),Xs),
    ( Xs == [] -> V = null ; sum_list(Xs,S), length(Xs,L), V is S/L ).
classes(Cs) :- findall(F,fault(F,_,_,_,_),Cs).
primary_t([P|_],P).
primary_p([],undetermined).
primary_p([P|_],P).
cls(Rs,C,_{label:C,tp:TP,fp:FP,fn:FN,precision:P,recall:R,f1:F1}) :-
    aggregate_all(count,(member(r(_,_,T,F,_,_,_),Rs),memberchk(C,T),memberchk(C,F)),TP),
    aggregate_all(count,(member(r(_,_,T,F,_,_,_),Rs),\+ memberchk(C,T),memberchk(C,F)),FP),
    aggregate_all(count,(member(r(_,_,T,F,_,_,_),Rs),memberchk(C,T),\+ memberchk(C,F)),FN),
    sd(TP,TP+FP,P), sd(TP,TP+FN,R), f1v(P,R,F1).
metrics(Rs,_{n:N,accuracy:Acc,coverage:Cov,macro_precision:MP,macro_recall:MR,macro_f1:MF,
             mean_ms:Mean,max_ms:Max,explainability:Ex,plan_validity:Pv,
             classes:Cls,labels:Labels,confusion:Conf}) :-
    length(Rs,N),
    aggregate_all(count,(member(r(_,_,T,F,_,_,_),Rs),exact(T,F)),Ok), Acc is Ok/N,
    aggregate_all(count,(member(r(_,_,_,F,_,_,_),Rs),F \== []),Cv), Cov is Cv/N,
    findall(M,member(r(_,_,_,_,M,_,_),Rs),Ts), sum_list(Ts,Sm), Mean is Sm/N, max_list(Ts,Max),
    ratio_of(Rs,6,Ex), ratio_of(Rs,7,Pv),
    classes(Cl), findall(D,(member(C,Cl),cls(Rs,C,D)),Cls0),
    include(has_support,Cls0,Cls),
    macro(Cls,precision,MP), macro(Cls,recall,MR), macro(Cls,f1,MF),
    append(Cl,[undetermined],Labels),
    findall(Row,(member(Lt,Labels),
        findall(K,(member(Lp,Labels),
            aggregate_all(count,(member(r(_,_,T,F,_,_,_),Rs),primary_t(T,Lt),primary_p(F,Lp)),K)),Row)),Conf).
has_support(D) :- get_dict(tp,D,TP), get_dict(fn,D,FN), TP+FN > 0.
macro(Cls,Key,V) :-
    findall(X,(member(D,Cls),get_dict(Key,D,X0),nz(X0,X)),Xs),
    ( Xs == [] -> V = null ; sum_list(Xs,S), length(Xs,L), V is S/L ).
cases(L) :- findall(case(I,T,Tr,D),case(I,T,Tr,D),L).
pass(M,S,Off,D) :- cases(Cs), findall(R,(member(C,Cs),run_case(M,S,Off,C,R)),Rs), metrics(Rs,D).

evaluate(_{modes:Modes,ablation:Abl,sensitivity:Sens,cases:Rows}) :-
    findall(_{mode:M,m:D},(member(M,[ded,ded_abd,ded_cbd,full]),pass(M,1.0,[],D)),Modes),
    findall(_{off:G,m:D},(member(G,[electrical,mechanical,thermal,drive,sensing]),pass(full,1.0,[G],D)),Abl),
    findall(_{scale:S,m:D},(member(S,[0.8,0.9,1.0,1.1,1.2]),pass(full,S,[],D)),Sens),
    cases(Cs),
    findall(_{id:Id,test:T,truth:Tr,final:Fi,ok:Ok,ms:Ms},
        (member(C,Cs),run_case(full,1.0,[],C,r(Id,T,Tr,Fi,Ms,_,_)),
         ( exact(Tr,Fi) -> Ok = true ; Ok = false )),Rows).
