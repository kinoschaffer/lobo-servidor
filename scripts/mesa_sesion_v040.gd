extends RefCounted
## Motor compartido por mesa local y servidor; las vistas salen filtradas.
const Motor = preload("res://scripts/partida_motor.gd")
var engine = Motor.new()
var humans: Array[int] = []
var ready_ids: Array[int] = []
var private_results: Dictionary = {}
var public_lines: Array[String] = []
var chat: Array[String] = []
var after_vote := false
var revision := 0
var phase_seconds := 0.0

func start(names: Array, seed_value: int = 0) -> void:
    engine.start_match(seed_value)
    humans.clear()
    for i in range(clampi(names.size(),1,8)):
        humans.append(i)
        engine.players[i].name = str(names[i]).strip_edges().left(20)
        if engine.players[i].name.is_empty(): engine.players[i].name = "Jugador %d" % (i+1)
    for i in range(humans.size(),8):
        engine.players[i].name = "Bot "+str(i+1)
    ready_ids.clear()
    private_results.clear()
    public_lines.assign(["Ocho vecinos: seis inocentes y dos impostores."])
    chat.clear()
    after_vote = false
    revision += 1
    phase_seconds = 0.0

func needs_turn(id: int) -> bool:
    if id not in humans or id in ready_ids: return false
    if engine.phase in ["role_assignment","dawn","discussion"]: return true
    return engine.phase in ["night","vote"] and bool(engine.players[id].alive)

func pending() -> Array[int]:
    var result: Array[int] = []
    for id in humans:
        if needs_turn(id): result.append(id)
    return result

func command(id: int, data: Dictionary) -> Dictionary:
    if id not in humans: return {"ok":false,"error":"No pertenecés a esta partida."}
    var op := str(data.get("op",""))
    var result: Dictionary = {"ok":true}
    if op=="chat":
        if engine.phase!="discussion" or not bool(engine.players[id].alive):
            return {"ok":false,"error":"Solo los vivos hablan durante el debate."}
        var message := str(data.get("text","")).strip_edges().left(220)
        if message.is_empty(): return {"ok":false,"error":"Escribí un mensaje."}
        chat.append(str(engine.players[id].name)+": "+message)
        if chat.size()>60: chat.pop_front()
        revision += 1
        return result
    if not needs_turn(id): return {"ok":false,"error":"Tu turno ya está confirmado."}
    if op=="action" and engine.phase=="night":
        result = engine.submit_action(id,str(data.get("kind","pass")),int(data.get("target",-1)))
    elif op=="vote" and engine.phase=="vote":
        result = engine.submit_vote(id,int(data.get("target",-1)))
    elif op!="ready" or engine.phase not in ["role_assignment","dawn","discussion"]:
        return {"ok":false,"error":"Esa acción no corresponde a esta fase."}
    if not bool(result.get("ok",false)): return result
    ready_ids.append(id)
    revision += 1
    if pending().is_empty(): _advance()
    return result

func _advance() -> void:
    match str(engine.phase):
        "role_assignment":
            engine.begin_night()
        "night":
            engine.fill_bot_actions(-1)
            var outcome: Dictionary = engine.resolve_night()
            private_results = outcome.get("private_results",{}).duplicate(true)
            public_lines.clear()
            for line in outcome.get("public_lines",[]): public_lines.append(str(line))
            if public_lines.is_empty(): public_lines.append("Nadie murió esta noche.")
            after_vote = false
        "dawn":
            if after_vote:
                engine.begin_night()
                after_vote = false
            else:
                engine.begin_discussion()
                _bot_debate()
        "discussion":
            engine.begin_vote()
        "vote":
            engine.fill_bot_votes(-1)
            var outcome: Dictionary = engine.resolve_vote()
            public_lines.clear()
            for line in outcome.get("public_lines",[]): public_lines.append(str(line))
            var totals: Dictionary = outcome.get("tally",{})
            for key in totals: public_lines.append(str(engine.players[int(key)].name)+": "+str(totals[key])+" voto(s).")
            public_lines.append("Abstenciones: "+str(outcome.get("skip",0)))
            after_vote = true
    ready_ids.clear()
    phase_seconds = 0.0
    revision += 1
    # Cuando solo quedan bots vivos, todavía se muestran los resultados a los humanos.
    if engine.phase in ["night","vote"] and pending().is_empty(): _advance()

func _bot_debate() -> void:
    chat.clear()
    for i in range(8):
        if i in humans or not bool(engine.players[i].alive): continue
        var own: Dictionary = engine.get_player_view(i)
        var message := "Prefiero comparar las pistas antes de votar."
        var report: Dictionary = private_results.get(i,{})
        if own.team=="impostor":
            message = "No tengo una prueba clara. Escuchemos a todos."
        elif not report.is_empty():
            message = str(report.get("message",message))
            if str(report.get("kind",""))=="investigate":
                engine.record_statement(i,"investigation",int(report.get("target",-1)),report.get("candidates",[]))
        chat.append(str(engine.players[i].name)+": "+message)

func view(id: int) -> Dictionary:
    if id not in humans: return {}
    var own: Dictionary = engine.get_player_view(id)
    var options: Dictionary = {}
    for kind in engine.allowed_actions(id): options[kind] = engine.valid_targets(id,kind)
    return {"phase":str(engine.phase),"round":int(engine.round_number),"winner":str(engine.winner),
        "own":own,"roster":engine.get_public_roster(),"result":private_results.get(id,{}).duplicate(true),
        "options":options,"public":public_lines.duplicate(),"chat":chat.duplicate(),"after_vote":after_vote,
        "submitted":id in ready_ids,"pending_count":pending().size(),"human_count":humans.size(),
        "revealed":engine.revealed_roster(),"revision":revision,
        "voice_allowed":engine.phase in ["discussion","endgame"] and (bool(own.alive) or engine.phase=="endgame")}

func expire_phase() -> void:
    # Solo servidor: desconexiones no bloquean la partida; faltas son pasar/abstener.
    for id in pending().duplicate():
        if engine.phase=="night": command(id,{"op":"action","kind":"pass","target":-1})
        elif engine.phase=="vote": command(id,{"op":"vote","target":-1})
        else: command(id,{"op":"ready"})

