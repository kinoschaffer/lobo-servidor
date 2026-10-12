extends RefCounted
## Motor local autoritativo. La UI solo consume las vistas filtradas.

const RULES_PATH: String = "res://datos/reglas_v0_1.json"
const ROLE_ACTIONS: Dictionary = {
	"doctor": "heal", "investigator": "investigate", "lookout": "watch",
	"police": "block", "trapper": "trap", "cleaner": "clean",
}
const ROLE_NAMES: Dictionary = {
	"doctor": "Médico", "investigator": "Investigador", "lookout": "Vigía",
	"police": "Policía", "trapper": "Trampero", "cleaner": "Limpiador",
	"insane": "Insano", "unknown": "Desconocido",
}
const PLAYER_NAMES: Array[String] = ["Tú", "Luna", "Bruno", "Mora", "Leo", "Vera", "Nico", "Sol"]
const PLAYER_COLORS: Array[String] = ["turquesa", "coral", "amarillo", "violeta", "azul", "rosa", "verde", "naranja"]

var phase: String = "lobby"
var round_number: int = 0
var winner: String = ""
var players: Array[Dictionary] = []
var votes: Dictionary = {}
var rules: Dictionary = {}

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _actions: Dictionary = {}
var _night_alive: Array[int] = []
var _blocked: Dictionary = {}
var _completed: Dictionary = {}
var _traps: Dictionary = {}
var _visits: Dictionary = {}
var _healed: Dictionary = {}
var _attacks: Array[int] = []
var _reports: Array[Dictionary] = []
var _results: Dictionary = {}
# Los bots guardan únicamente sus informes privados y totales públicos.
var _bot_memory: Dictionary = {}
var _previous_vote_tally: Dictionary = {}
var _last_night_deaths: int = 0
var _statements: Array[Dictionary] = []


func start_match(seed_value: int = 0) -> void:
	phase = "lobby"
	round_number = 0
	winner = ""
	players.clear()
	votes.clear()
	_actions.clear()
	_night_alive.clear()
	_blocked.clear()
	_completed.clear()
	_traps.clear()
	_visits.clear()
	_healed.clear()
	_attacks.clear()
	_reports.clear()
	_results.clear()
	_bot_memory.clear()
	_previous_vote_tally.clear()
	_last_night_deaths = 0
	_statements.clear()
	rules.clear()
	if not FileAccess.file_exists(RULES_PATH):
		push_error("No se encontró la configuración de reglas: " + RULES_PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RULES_PATH))
	if not parsed is Dictionary:
		push_error("La configuración de reglas no es un objeto JSON válido.")
		return
	rules = parsed as Dictionary
	if seed_value == 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value
	var deck: Dictionary = rules.get("first_deck", {}) as Dictionary
	var cards: Array = (deck.get("cards", []) as Array).duplicate(true)
	if cards.size() != 8:
		push_error("El primer mazo requiere ocho tarjetas.")
		return
	_shuffle(cards)
	for id: int in range(cards.size()):
		var card: Dictionary = cards[id] as Dictionary
		var role: String = str(card.get("role", ""))
		var notes: Array[String] = []
		players.append({
			"id": id, "name": PLAYER_NAMES[id], "color": PLAYER_COLORS[id],
			"role": role, "apparent_role": str(card.get("apparent_role", role)),
			"team": str(card.get("team", "innocent")), "alive": true,
			"cleaned": false, "last_action": "pass", "last_target": -1,
			"notes": notes, "investigations": {},
		})
	phase = "role_assignment"


func begin_night() -> void:
	if winner != "" or phase not in ["role_assignment", "dawn"]:
		return
	phase = "night"
	round_number += 1
	_statements.clear()
	_actions.clear()
	votes.clear()
	_night_alive.clear()
	for player: Dictionary in players:
		if bool(player.get("alive", false)):
			_night_alive.append(int(player["id"]))


func allowed_actions(actor_id: int) -> Array[String]:
	var available: Array[String] = []
	var actor: Dictionary = _player(actor_id)
	if actor.is_empty() or not bool(actor.get("alive", false)):
		return available
	if str(actor.get("team", "")) == "impostor":
		available.append("kill")
	var apparent_role: String = str(actor.get("apparent_role", actor.get("role", "")))
	var ability: String = str(ROLE_ACTIONS.get(apparent_role, ""))
	if ability != "":
		available.append(ability)
	available.append("pass")
	return available


func valid_targets(actor_id: int, kind: String) -> Array[int]:
	var targets: Array[int] = []
	if kind == "pass" or not allowed_actions(actor_id).has(kind):
		return targets
	var actor: Dictionary = _player(actor_id)
	for target: Dictionary in players:
		var target_id: int = int(target["id"])
		if not bool(target.get("alive", false)) or target_id == actor_id:
			continue
		if kind == "kill" and str(target.get("team", "")) == str(actor.get("team", "")):
			continue
		if kind in ["heal", "block"] and str(actor.get("last_action", "")) == kind and int(actor.get("last_target", -1)) == target_id:
			continue
		targets.append(target_id)
	return targets


func submit_action(actor_id: int, kind: String, target_id: int = -1) -> Dictionary:
	if phase != "night":
		return _error("Las acciones solo se eligen durante la noche.")
	var actor: Dictionary = _player(actor_id)
	if actor.is_empty() or not _night_alive.has(actor_id) or not bool(actor.get("alive", false)):
		return _error("Este jugador no puede actuar.")
	if not allowed_actions(actor_id).has(kind):
		return _error("Tu tarjeta no permite esa acción.")
	if kind != "pass" and not valid_targets(actor_id, kind).has(target_id):
		return _error("Objetivo inválido: debe estar vivo y respetar las restricciones de tu habilidad.")
	_actions[actor_id] = {"kind": kind, "target": target_id if kind != "pass" else -1}
	return {"ok": true, "error": ""}


func get_player_view(actor_id: int) -> Dictionary:
	var actor: Dictionary = _player(actor_id)
	if actor.is_empty():
		return {}
	var apparent_role: String = str(actor.get("apparent_role", actor.get("role", "")))
	var allies: Array[int] = []
	if str(actor.get("team", "")) == "impostor":
		for other: Dictionary in players:
			if int(other["id"]) != actor_id and bool(other.get("alive", false)) and str(other.get("team", "")) == "impostor":
				allies.append(int(other["id"]))
	return {
		"id": actor_id, "alive": bool(actor.get("alive", false)),
		"role": apparent_role, "role_name": str(ROLE_NAMES.get(apparent_role, apparent_role)),
		"team": str(actor.get("team", "")), "action_kinds": allowed_actions(actor_id),
		"notes": (actor.get("notes", []) as Array).duplicate(),
		"allies": allies, "roster": get_public_roster(),
		"statements": _statements.duplicate(true),
	}


func get_public_roster() -> Array[Dictionary]:
	var roster: Array[Dictionary] = []
	for player: Dictionary in players:
		var public_role: String = ""
		var public_team: String = ""
		if not bool(player.get("alive", false)):
			if bool(player.get("cleaned", false)):
				public_role = "unknown"
				public_team = "unknown"
			else:
				public_role = str(player.get("apparent_role", player.get("role", "")))
				public_team = str(player.get("team", ""))
		roster.append({
			"id": int(player["id"]), "name": str(player["name"]),
			"alive": bool(player.get("alive", false)),
			"public_role": public_role, "public_team": public_team,
		})
	return roster


func revealed_roster() -> Array[Dictionary]:
	var roster: Array[Dictionary] = []
	if phase != "endgame":
		return roster
	for player: Dictionary in players:
		var role: String = str(player.get("role", ""))
		roster.append({
			"id": int(player["id"]), "name": str(player["name"]),
			"alive": bool(player.get("alive", false)), "role": role,
			"role_name": str(ROLE_NAMES.get(role, role)), "team": str(player.get("team", "")),
			"cleaned": bool(player.get("cleaned", false)),
		})
	return roster


func fill_bot_actions(exclude_id: int = 0) -> void:
	if phase != "night":
		return
	for actor_id: int in _night_alive:
		if actor_id == exclude_id or _actions.has(actor_id):
			continue
		# Solo usa la tarjeta propia, objetivos legales y aliados conocidos.
		var view: Dictionary = get_player_view(actor_id)
		var choices: Array[String] = allowed_actions(actor_id)
		var kind: String = "pass"
		var roll: float = _rng.randf()
		if str(view.get("team", "")) == "impostor" and roll < 0.70:
			kind = "kill"
		elif roll < 0.95:
			for choice: String in choices:
				if choice not in ["pass", "kill"]:
					kind = choice
					break
		var targets: Array[int] = valid_targets(actor_id, kind)
		if kind != "pass" and not targets.is_empty():
			submit_action(actor_id, kind, _bot_pick_target(actor_id, kind, targets))
		else:
			submit_action(actor_id, "pass")


func resolve_night() -> Dictionary:
	var empty_deaths: Array[int] = []
	var public_lines: Array[String] = []
	if phase != "night":
		return {"deaths": empty_deaths, "private_results": {}, "public_lines": public_lines, "winner": winner}
	_blocked.clear()
	_completed.clear()
	_traps.clear()
	_visits.clear()
	_healed.clear()
	_attacks.clear()
	_reports.clear()
	_results.clear()
	for actor_id: int in _night_alive:
		if not _actions.has(actor_id):
			_actions[actor_id] = {"kind": "pass", "target": -1}
		var submitted: Dictionary = _actions[actor_id] as Dictionary
		var actor: Dictionary = _player(actor_id)
		# La prohibición de repetición depende de la última elección, incluso bloqueada.
		actor["last_action"] = str(submitted["kind"])
		actor["last_target"] = int(submitted["target"])
	var tiers: Array = [["block"], ["trap"], ["heal"], ["clean"], ["kill"], ["investigate", "watch"]]
	for tier_value: Variant in tiers:
		var tier: Array = tier_value as Array
		var order: Array = []
		for actor_id: int in _night_alive:
			if tier.has(str((_actions[actor_id] as Dictionary).get("kind", ""))):
				order.append(actor_id)
		_shuffle(order)
		for value: Variant in order:
			_execute_action(int(value))
	# Ningún informe se genera antes de que terminen todas las visitas.
	for report: Dictionary in _reports:
		_finish_report(report)
	for actor_id: int in _night_alive:
		if str((_actions[actor_id] as Dictionary).get("kind", "")) == "pass":
			_set_result(actor_id, "passed", "Pasaste esta noche.")
	var deaths: Array[int] = []
	for target_id: int in _attacks:
		if _healed.has(target_id) or deaths.has(target_id):
			continue
		var target: Dictionary = _player(target_id)
		if not target.is_empty() and bool(target.get("alive", false)):
			target["alive"] = false
			deaths.append(target_id)
	_last_night_deaths = deaths.size()
	for actor_id: int in _night_alive:
		var result: Dictionary = _results.get(actor_id, {}) as Dictionary
		if not result.is_empty():
			_remember_bot_result(actor_id, result)
			_append_note(actor_id, "Noche %d: %s" % [round_number, str(result.get("message", ""))])
	if deaths.is_empty():
		public_lines.append("Amaneció sin nuevas muertes.")
	else:
		for target_id: int in deaths:
			public_lines.append("%s murió durante la noche." % _name(target_id))
	_check_victory()
	phase = "endgame" if winner != "" else "dawn"
	return {"deaths": deaths, "private_results": _results.duplicate(true), "public_lines": public_lines, "winner": winner}


func _execute_action(actor_id: int) -> void:
	var action: Dictionary = _actions[actor_id] as Dictionary
	var kind: String = str(action["kind"])
	var target_id: int = int(action["target"])
	if _blocked.has(actor_id):
		_completed[actor_id] = true
		_set_result(actor_id, "blocked", "Tu acción fue bloqueada; no visitaste ninguna casa.")
		return
	# Una visita interceptada sigue siendo visible para el Vigía.
	var visitors: Array = _visits.get(target_id, []) as Array
	visitors.append(actor_id)
	_visits[target_id] = visitors
	var installed: Array = _traps.get(target_id, []) as Array
	if not installed.is_empty():
		var trapper_id: int = int(installed.pop_front())
		_traps[target_id] = installed
		_completed[actor_id] = true
		_set_result(actor_id, "trapped", "Una trampa interceptó tu visita; tu acción no tuvo efecto.")
		var trapper_result: Dictionary = _results.get(trapper_id, {}) as Dictionary
		trapper_result["message"] = "La trampa de %s interceptó una visita posterior." % _name(target_id)
		trapper_result["intercepted"] = true
		_results[trapper_id] = trapper_result
		return
	_completed[actor_id] = true
	var actor: Dictionary = _player(actor_id)
	var target: Dictionary = _player(target_id)
	if str(actor.get("role", "")) == "insane":
		_reports.append({"actor": actor_id, "target": target_id, "kind": kind, "fictional": true})
		return
	match kind:
		"block":
			if not _completed.has(target_id) and str((_actions.get(target_id, {}) as Dictionary).get("kind", "pass")) != "pass":
				_blocked[target_id] = true
				_set_result(actor_id, "success", "Bloqueaste la acción pendiente de %s." % _name(target_id))
			else:
				_set_result(actor_id, "no_effect", "Visitaste a %s; no quedaba una acción pendiente que bloquear." % _name(target_id))
		"trap":
			var traps: Array = _traps.get(target_id, []) as Array
			traps.append(actor_id)
			_traps[target_id] = traps
			_set_result(actor_id, "success", "Instalaste una trampa en %s; ninguna visita posterior la activó." % _name(target_id))
		"heal":
			_healed[target_id] = true
			_set_result(actor_id, "success", "Protegiste a %s contra todos los ataques ordinarios de esta noche." % _name(target_id))
		"clean":
			target["cleaned"] = true
			_set_result(actor_id, "success", "Ocultaste la identidad informativa de %s hasta el final de la partida." % _name(target_id))
		"kill":
			_attacks.append(target_id)
			_set_result(actor_id, "success", "Realizaste un ataque contra %s; el resultado se conocerá al amanecer." % _name(target_id))
		"investigate", "watch":
			_reports.append({"actor": actor_id, "target": target_id, "kind": kind, "fictional": false})


func _finish_report(report: Dictionary) -> void:
	var actor_id: int = int(report["actor"])
	var target_id: int = int(report["target"])
	var kind: String = str(report["kind"])
	var actor: Dictionary = _player(actor_id)
	var fictional: bool = bool(report.get("fictional", false))
	if kind == "watch":
		var visitor_count: int = 0
		for visitor: Variant in (_visits.get(target_id, []) as Array):
			if int(visitor) != actor_id:
				visitor_count += 1
		if fictional:
			visitor_count = _rng.randi_range(0, 3)
		_set_result(actor_id, "success", "%s recibió %d visita(s) de otros jugadores." % [_name(target_id), visitor_count])
		(_results[actor_id] as Dictionary)["visitor_count"] = visitor_count
		return
	if kind != "investigate":
		_set_result(actor_id, "success", "Usaste tu habilidad en %s." % _name(target_id))
		return
	var memory: Dictionary = actor.get("investigations", {}) as Dictionary
	var previous: Dictionary = memory.get(target_id, {}) as Dictionary
	var candidates: Array[Dictionary] = []
	var identity_key: String = ""
	if fictional:
		# No consulta ni el rol, ni el bando, ni la limpieza del objetivo.
		identity_key = "imagined"
		if str(previous.get("identity", "")) == identity_key:
			for saved: Variant in (previous.get("candidates", []) as Array):
				candidates.append((saved as Dictionary).duplicate())
		else:
			candidates = _random_pair()
	else:
		var identity: Dictionary = _informative_identity(target_id)
		if str(identity.get("role", "")) == "unknown":
			_set_result(actor_id, "unknown", "La identidad de %s está oculta; no obtuviste candidatos." % _name(target_id))
			(_results[actor_id] as Dictionary)["candidates"] = candidates
			return
		identity_key = "%s:%s" % [str(identity["role"]), str(identity["team"])]
		if str(previous.get("identity", "")) == identity_key:
			for saved: Variant in (previous.get("candidates", []) as Array):
				candidates.append((saved as Dictionary).duplicate())
		else:
			var other_team: String = "impostor" if str(identity["team"]) == "innocent" else "innocent"
			candidates.append(identity.duplicate())
			candidates.append({"role": _random_role(other_team), "team": other_team})
			_shuffle(candidates)
	memory[target_id] = {"identity": identity_key, "candidates": candidates.duplicate(true)}
	actor["investigations"] = memory
	var descriptions: Array[String] = []
	for candidate: Dictionary in candidates:
		descriptions.append("%s (%s)" % [str(ROLE_NAMES.get(str(candidate["role"]), str(candidate["role"]))), "inocente" if str(candidate["team"]) == "innocent" else "impostor"])
	_set_result(actor_id, "success", "%s podría ser %s o %s." % [_name(target_id), descriptions[0], descriptions[1]])
	(_results[actor_id] as Dictionary)["candidates"] = candidates


func begin_discussion() -> void:
	if phase == "dawn" and winner == "":
		phase = "discussion"


func begin_vote() -> void:
	if phase in ["discussion", "dawn"] and winner == "":
		phase = "vote"
		votes.clear()


func submit_vote(voter: int, target: int = -1) -> Dictionary:
	if phase != "vote":
		return _error("Todavía no es la fase de votación.")
	var actor: Dictionary = _player(voter)
	if actor.is_empty() or not bool(actor.get("alive", false)):
		return _error("Solo los jugadores vivos pueden votar.")
	if target != -1:
		var candidate: Dictionary = _player(target)
		if candidate.is_empty() or target == voter or not bool(candidate.get("alive", false)):
			return _error("Debes elegir otro jugador vivo o abstenerte.")
	votes[voter] = target
	return {"ok": true, "error": ""}


func fill_bot_votes(exclude_id: int = 0) -> void:
	if phase != "vote":
		return
	for player: Dictionary in players:
		var actor_id: int = int(player["id"])
		if actor_id == exclude_id or not bool(player.get("alive", false)) or votes.has(actor_id):
			continue
		var view: Dictionary = get_player_view(actor_id)
		var known_allies: Array = view.get("allies", []) as Array
		var candidates: Array[int] = [-1]
		for public_player: Variant in (view.get("roster", []) as Array):
			var public_data: Dictionary = public_player as Dictionary
			var target_id: int = int(public_data["id"])
			if bool(public_data.get("alive", false)) and target_id != actor_id and not known_allies.has(target_id):
				candidates.append(target_id)
		submit_vote(actor_id, _bot_pick_vote(actor_id, candidates))


func resolve_vote() -> Dictionary:
	var tally: Dictionary = {}
	var skip_count: int = 0
	var eliminated: int = -1
	var public_lines: Array[String] = []
	if phase != "vote":
		return {"eliminated": eliminated, "tally": tally, "skip": skip_count, "winner": winner, "public_lines": public_lines}
	for player: Dictionary in players:
		if not bool(player.get("alive", false)):
			continue
		var actor_id: int = int(player["id"])
		var target_id: int = int(votes.get(actor_id, -1))
		var target: Dictionary = _player(target_id)
		if target_id == -1 or target_id == actor_id or target.is_empty() or not bool(target.get("alive", false)):
			skip_count += 1
		else:
			tally[target_id] = int(tally.get(target_id, 0)) + 1
	var highest: int = 0
	var ties: int = 0
	for value: Variant in tally:
		var candidate_id: int = int(value)
		var count: int = int(tally[value])
		if count > highest:
			highest = count
			eliminated = candidate_id
			ties = 1
		elif count == highest:
			ties += 1
	if ties != 1 or highest <= skip_count:
		eliminated = -1
	_previous_vote_tally = tally.duplicate()
	if eliminated != -1:
		_player(eliminated)["alive"] = false
		public_lines.append("%s fue expulsado con %d voto(s)." % [_name(eliminated), highest])
	else:
		public_lines.append("Nadie fue expulsado: hubo empate o la abstención alcanzó al candidato más votado.")
	_check_victory()
	phase = "endgame" if winner != "" else "dawn"
	return {"eliminated": eliminated, "tally": tally, "skip": skip_count, "winner": winner, "public_lines": public_lines}


func _check_victory() -> void:
	var innocent_count: int = 0
	var impostor_count: int = 0
	for player: Dictionary in players:
		if not bool(player.get("alive", false)):
			continue
		if str(player.get("team", "")) == "impostor":
			impostor_count += 1
		else:
			innocent_count += 1
	winner = ""
	if innocent_count + impostor_count == 0:
		winner = "draw"
	elif impostor_count == 0:
		winner = "innocent"
	elif impostor_count >= innocent_count:
		winner = "impostor"


func _informative_identity(target_id: int) -> Dictionary:
	var target: Dictionary = _player(target_id)
	if bool(target.get("cleaned", false)):
		return {"role": "unknown", "team": "unknown"}
	return {"role": str(target.get("apparent_role", target.get("role", ""))), "team": str(target.get("team", ""))}


func _random_pair() -> Array[Dictionary]:
	var pair: Array[Dictionary] = [
		{"role": _random_role("innocent"), "team": "innocent"},
		{"role": _random_role("impostor"), "team": "impostor"},
	]
	_shuffle(pair)
	return pair


func _random_role(team: String) -> String:
	var possible: Array[String] = []
	for value: Variant in (rules.get("roles", []) as Array):
		var role_data: Dictionary = value as Dictionary
		var role_id: String = str(role_data.get("id", ""))
		if str(role_data.get("stage", "")) == "core" and role_id != "insane" and (role_data.get("teams", []) as Array).has(team):
			possible.append(role_id)
	if possible.is_empty():
		return "police"
	return possible[_rng.randi_range(0, possible.size() - 1)]


func _set_result(actor_id: int, status: String, message: String) -> void:
	var action: Dictionary = _actions.get(actor_id, {"kind": "pass", "target": -1}) as Dictionary
	_results[actor_id] = {"kind": str(action["kind"]), "target": int(action["target"]), "status": status, "message": message}


func _append_note(actor_id: int, message: String) -> void:
	var actor: Dictionary = _player(actor_id)
	var notes: Array = actor.get("notes", []) as Array
	notes.append(message)
	actor["notes"] = notes


func _player(player_id: int) -> Dictionary:
	for player: Dictionary in players:
		if int(player.get("id", -1)) == player_id:
			return player
	return {}


func _name(player_id: int) -> String:
	return str(_player(player_id).get("name", "Jugador"))


func _shuffle(items: Array) -> void:
	for index: int in range(items.size() - 1, 0, -1):
		var other: int = _rng.randi_range(0, index)
		var saved: Variant = items[index]
		items[index] = items[other]
		items[other] = saved


func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}

func _remember_bot_result(actor_id: int, report: Dictionary) -> void:
	# Copia exactamente la información que recibe ese dueño, sin identidad real
	# ni el indicador «fictional» del Insano utilizado internamente al resolver.
	var memory: Dictionary = _bot_memory.get(actor_id, {"latest": {}, "investigations": {}, "cleaned_targets": []}) as Dictionary
	memory["latest"] = report.duplicate(true)
	var target_id: int = int(report.get("target", -1))
	if str(report.get("kind", "")) == "investigate" and str(report.get("status", "")) in ["success", "unknown"]:
		var seen: Dictionary = memory.get("investigations", {}) as Dictionary
		seen[target_id] = (report.get("candidates", []) as Array).duplicate(true)
		memory["investigations"] = seen
	if str(report.get("kind", "")) == "clean" and str(report.get("status", "")) == "success":
		var cleaned: Array = memory.get("cleaned_targets", []) as Array
		if not cleaned.has(target_id):
			cleaned.append(target_id)
		memory["cleaned_targets"] = cleaned
	_bot_memory[actor_id] = memory


func _bot_remaining_cards(actor_id: int) -> Dictionary:
	# El mazo y las tarjetas públicas son reglas conocidas. Insano cuenta por
	# su rol aparente: esta deducción nunca consulta su asignación secreta.
	var remaining: Dictionary = {}
	for card_value: Variant in ((rules.get("first_deck", {}) as Dictionary).get("cards", []) as Array):
		var card: Dictionary = card_value as Dictionary
		var role: String = str(card.get("apparent_role", card.get("role", "")))
		var key: String = "%s:%s" % [str(card.get("team", "")), role]
		remaining[key] = int(remaining.get(key, 0)) + 1
	var view: Dictionary = get_player_view(actor_id)
	var known_cards: Array[Dictionary] = [{"role": str(view.get("role", "")), "team": str(view.get("team", ""))}]
	for entry: Dictionary in get_public_roster():
		if not bool(entry.get("alive", false)) and str(entry.get("public_role", "")) not in ["", "unknown"]:
			known_cards.append({"role": str(entry["public_role"]), "team": str(entry["public_team"])})
	for known: Dictionary in known_cards:
		var key: String = "%s:%s" % [str(known["team"]), str(known["role"])]
		remaining[key] = maxi(0, int(remaining.get(key, 0)) - 1)
	return remaining


func _bot_suspicion(actor_id: int, target_id: int) -> float:
	var suspicion: float = 0.0
	var memory: Dictionary = _bot_memory.get(actor_id, {}) as Dictionary
	var seen: Dictionary = memory.get("investigations", {}) as Dictionary
	var candidates: Array = seen.get(target_id, []) as Array
	if not candidates.is_empty():
		var remaining: Dictionary = _bot_remaining_cards(actor_id)
		var innocent_possible: int = 0
		var impostor_possible: int = 0
		for value: Variant in candidates:
			var candidate: Dictionary = value as Dictionary
			var key: String = "%s:%s" % [str(candidate.get("team", "")), str(candidate.get("role", ""))]
			if str(candidate.get("team", "")) == "impostor":
				impostor_possible += int(remaining.get(key, 0))
			else:
				innocent_possible += int(remaining.get(key, 0))
		if innocent_possible == 0 and impostor_possible > 0:
			suspicion += 3.0
		elif impostor_possible == 0 and innocent_possible > 0:
			suspicion -= 3.0
		elif innocent_possible + impostor_possible > 0:
			suspicion += float(impostor_possible - innocent_possible) / float(impostor_possible + innocent_possible)
	var latest: Dictionary = memory.get("latest", {}) as Dictionary
	if str(latest.get("kind", "")) == "block" and str(latest.get("status", "")) == "success" and int(latest.get("target", -1)) == target_id and _last_night_deaths == 0:
		# Es una sospecha débil: una noche tranquila también puede ser curación.
		suspicion += 0.7
	return suspicion


func _bot_pick_target(actor_id: int, kind: String, targets: Array[int]) -> int:
	var memory: Dictionary = _bot_memory.get(actor_id, {}) as Dictionary
	var latest: Dictionary = memory.get("latest", {}) as Dictionary
	var seen: Dictionary = memory.get("investigations", {}) as Dictionary
	var cleaned: Array = memory.get("cleaned_targets", []) as Array
	var chosen: int = targets[0]
	var best_score: float = -INF
	for target_id: int in targets:
		var score: float = _rng.randf_range(-0.7, 0.7)
		var suspicion: float = _bot_suspicion(actor_id, target_id)
		if kind == "block":
			score += suspicion
		elif kind in ["heal", "trap", "watch"]:
			score -= suspicion
		elif kind == "investigate":
			score += 2.0 if not seen.has(target_id) else -2.0
		elif kind == "clean" and cleaned.has(target_id):
			score -= 4.0
		elif kind == "kill" and str(latest.get("kind", "")) == "kill" and int(latest.get("target", -1)) == target_id:
			# El objetivo sobrevivió al ataque previo: probar otra casa evita
			# insistir a ciegas contra una posible cura o trampa.
			score -= 1.5
		if score > best_score:
			best_score = score
			chosen = target_id
	return chosen


func _bot_pick_vote(actor_id: int, candidates: Array[int]) -> int:
	var view: Dictionary = get_player_view(actor_id)
	var impostor: bool = str(view.get("team", "")) == "impostor"
	var chosen: int = -1
	var best_score: float = -INF
	for target_id: int in candidates:
		if target_id == -1:
			continue
		var score: float = _rng.randf_range(-0.65, 0.65)
		if not impostor:
			score += _bot_suspicion(actor_id, target_id)
		score += _bot_statement_weight(actor_id, target_id)
		# Totales públicos de la votación anterior; ninguna boleta oculta ni
		# selección todavía pendiente de otros jugadores entra en la decisión.
		score += minf(0.8, float(_previous_vote_tally.get(target_id, 0)) * 0.16)
		if score > best_score:
			best_score = score
			chosen = target_id
	if best_score < -1.5 or (best_score < 0.6 and _rng.randf() < 0.08):
		return -1
	return chosen


func record_statement(actor_id: int, kind: String, target_id: int = -1, candidates: Array = []) -> bool:
	if phase != "discussion" or kind not in ["accuse", "defend", "claim", "investigate", "watch", "block", "heal", "pass"]:
		return false
	var actor: Dictionary = _player(actor_id)
	if actor.is_empty() or not bool(actor.get("alive", false)):
		return false
	if kind not in ["claim", "pass"]:
		var target: Dictionary = _player(target_id)
		if target.is_empty() or target_id == actor_id or not bool(target.get("alive", false)):
			return false
	elif target_id != -1:
		return false
	if not _save_candidates_valid(candidates) or (kind != "investigate" and not candidates.is_empty()):
		return false
	if kind == "investigate" and candidates.size() != 2:
		return false
	var statement: Dictionary = {"actor": actor_id, "kind": kind, "target": target_id, "candidates": candidates.duplicate(true)}
	# Una declaración por clase y jugador: editarla no multiplica su influencia.
	for index: int in range(_statements.size()):
		if int(_statements[index].get("actor", -1)) == actor_id and str(_statements[index].get("kind", "")) == kind:
			_statements[index] = statement
			return true
	_statements.append(statement)
	return true


func _bot_statement_weight(actor_id: int, target_id: int) -> float:
	var weight: float = 0.0
	for statement: Dictionary in _statements:
		if int(statement.get("actor", -1)) == actor_id or int(statement.get("target", -1)) != target_id:
			continue
		match str(statement.get("kind", "")):
			"accuse":
				weight += 0.25
			"defend":
				weight -= 0.20
			"heal":
				weight -= 0.12
			"block":
				if _last_night_deaths == 0:
					weight += 0.15
			"investigate":
				var remaining: Dictionary = _bot_remaining_cards(actor_id)
				var innocent_possible: int = 0
				var impostor_possible: int = 0
				for value: Variant in (statement.get("candidates", []) as Array):
					var candidate: Dictionary = value as Dictionary
					var key: String = "%s:%s" % [str(candidate["team"]), str(candidate["role"])]
					if str(candidate["team"]) == "impostor":
						impostor_possible += int(remaining.get(key, 0))
					else:
						innocent_possible += int(remaining.get(key, 0))
				if innocent_possible == 0 and impostor_possible > 0:
					weight += 0.55
				elif impostor_possible == 0 and innocent_possible > 0:
					weight -= 0.50
	# Un relato nunca se transforma en prueba ni garantiza un voto.
	return clampf(weight, -0.75, 0.75)


func get_save_data() -> Dictionary:
	if players.size() != 8 or rules.is_empty():
		return {}
	var state: Dictionary = {
		"phase": phase, "round_number": round_number, "winner": winner,
		"players": players.duplicate(true), "votes": votes.duplicate(true),
		"rng_seed": str(_rng.seed), "rng_state": str(_rng.state),
		"actions": _actions.duplicate(true), "night_alive": _night_alive.duplicate(),
		"blocked": _blocked.duplicate(true), "completed": _completed.duplicate(true),
		"traps": _traps.duplicate(true), "visits": _visits.duplicate(true),
		"healed": _healed.duplicate(true), "attacks": _attacks.duplicate(),
		"reports": _reports.duplicate(true), "results": _results.duplicate(true),
		"bot_memory": _bot_memory.duplicate(true), "previous_vote_tally": _previous_vote_tally.duplicate(true),
		"last_night_deaths": _last_night_deaths, "statements": _statements.duplicate(true),
	}
	return {"schema_version": 1, "ruleset_id": str(rules.get("ruleset_id", "")), "state": _save_pack(state)}


func restore_match(data: Dictionary) -> bool:
	# Desempaquetar y validar en variables locales; un archivo corrupto jamás
	# borra la partida que ya está funcionando.
	if data.get("schema_version", 0) != 1 or not data.has("state"):
		return false
	var parsed_rules: Variant = JSON.parse_string(FileAccess.get_file_as_string(RULES_PATH))
	if not parsed_rules is Dictionary or data.get("ruleset_id", "") != (parsed_rules as Dictionary).get("ruleset_id", ""):
		return false
	var decoded: Dictionary = _save_unpack(data["state"])
	if not bool(decoded.get("ok", false)) or not decoded.get("value") is Dictionary:
		return false
	var state: Dictionary = decoded["value"] as Dictionary
	if not _save_state_valid(state, parsed_rules as Dictionary):
		return false
	rules = (parsed_rules as Dictionary).duplicate(true)
	phase = str(state["phase"])
	round_number = int(state["round_number"])
	winner = str(state["winner"])
	players.clear()
	for value: Variant in (state["players"] as Array):
		players.append((value as Dictionary).duplicate(true))
	votes = (state["votes"] as Dictionary).duplicate(true)
	_rng.seed = str(state["rng_seed"]).to_int()
	_rng.state = str(state["rng_state"]).to_int()
	_actions = (state["actions"] as Dictionary).duplicate(true)
	_night_alive.clear()
	for value: Variant in (state["night_alive"] as Array):
		_night_alive.append(int(value))
	_blocked = (state["blocked"] as Dictionary).duplicate(true)
	_completed = (state["completed"] as Dictionary).duplicate(true)
	_traps = (state["traps"] as Dictionary).duplicate(true)
	_visits = (state["visits"] as Dictionary).duplicate(true)
	_healed = (state["healed"] as Dictionary).duplicate(true)
	_attacks.clear()
	for value: Variant in (state["attacks"] as Array):
		_attacks.append(int(value))
	_reports.clear()
	for value: Variant in (state["reports"] as Array):
		_reports.append((value as Dictionary).duplicate(true))
	_results = (state["results"] as Dictionary).duplicate(true)
	_bot_memory = (state["bot_memory"] as Dictionary).duplicate(true)
	_previous_vote_tally = (state["previous_vote_tally"] as Dictionary).duplicate(true)
	_last_night_deaths = int(state["last_night_deaths"])
	_statements.clear()
	for value: Variant in (state["statements"] as Array):
		_statements.append((value as Dictionary).duplicate(true))
	return true


func _save_pack(value: Variant) -> Variant:
	if value is Dictionary:
		var entries: Array[Dictionary] = []
		for key: Variant in value:
			entries.append({"key": str(key), "integer_key": key is int, "value": _save_pack(value[key])})
		return {"type": "dictionary", "entries": entries}
	if value is Array:
		var items: Array = []
		for item: Variant in value:
			items.append(_save_pack(item))
		return items
	return value


func _save_unpack(value: Variant, depth: int = 0) -> Dictionary:
	if depth > 24:
		return {"ok": false}
	if value is Dictionary:
		var packed: Dictionary = value as Dictionary
		if packed.get("type", "") != "dictionary" or not packed.get("entries") is Array or (packed["entries"] as Array).size() > 1024:
			return {"ok": false}
		var unpacked: Dictionary = {}
		for item: Variant in (packed["entries"] as Array):
			if not item is Dictionary:
				return {"ok": false}
			var entry: Dictionary = item as Dictionary
			if not entry.get("key") is String or not entry.get("integer_key") is bool or not entry.has("value"):
				return {"ok": false}
			var key: Variant = entry["key"]
			if bool(entry["integer_key"]):
				if not _save_integer_string_valid(key):
					return {"ok": false}
				key = str(key).to_int()
			if unpacked.has(key):
				return {"ok": false}
			var child: Dictionary = _save_unpack(entry["value"], depth + 1)
			if not bool(child.get("ok", false)):
				return {"ok": false}
			unpacked[key] = child["value"]
		return {"ok": true, "value": unpacked}
	if value is Array:
		if (value as Array).size() > 10000:
			return {"ok": false}
		var items: Array = []
		for item: Variant in (value as Array):
			var child: Dictionary = _save_unpack(item, depth + 1)
			if not bool(child.get("ok", false)):
				return {"ok": false}
			items.append(child["value"])
		return {"ok": true, "value": items}
	if value is float:
		if not is_finite(float(value)) or floor(float(value)) != float(value) or absf(float(value)) > 9007199254740991.0:
			return {"ok": false}
		return {"ok": true, "value": int(value)}
	if value is int or value is String or value is bool:
		return {"ok": true, "value": value}
	return {"ok": false}


func _save_id(value: Variant, allow_skip: bool = false) -> bool:
	return value is int and int(value) >= (-1 if allow_skip else 0) and int(value) < 8


func _save_ids_valid(value: Variant, unique: bool = false) -> bool:
	if not value is Array or (value as Array).size() > 8:
		return false
	var seen: Dictionary = {}
	for id: Variant in (value as Array):
		if not _save_id(id) or (unique and seen.has(id)):
			return false
		seen[id] = true
	return true


func _save_candidates_valid(value: Variant) -> bool:
	if not value is Array or (value as Array).size() not in [0, 2]:
		return false
	var teams_seen: Dictionary = {}
	for item: Variant in (value as Array):
		if not item is Dictionary:
			return false
		var candidate: Dictionary = item as Dictionary
		if candidate.get("role", "") not in ROLE_ACTIONS or candidate.get("team", "") not in ["innocent", "impostor"]:
			return false
		teams_seen[candidate["team"]] = true
	return (value as Array).is_empty() or teams_seen.size() == 2


func _save_action_valid(actor_id: int, value: Variant, saved_players: Array) -> bool:
	if not value is Dictionary:
		return false
	var action: Dictionary = value as Dictionary
	if actor_id < 0 or actor_id >= saved_players.size() or not saved_players[actor_id] is Dictionary:
		return false
	var actor: Dictionary = saved_players[actor_id] as Dictionary
	var permitted: Array[String] = ["pass", str(ROLE_ACTIONS.get(str(actor.get("apparent_role", "")), ""))]
	if str(actor.get("team", "")) == "impostor":
		permitted.append("kill")
	if action.get("kind", "") not in permitted or not _save_id(action.get("target"), true):
		return false
	var target_id: int = int(action["target"])
	if str(action["kind"]) == "pass":
		return target_id == -1
	if target_id < 0 or target_id == actor_id:
		return false
	if target_id >= saved_players.size() or not saved_players[target_id] is Dictionary:
		return false
	return str(action["kind"]) != "kill" or str((saved_players[target_id] as Dictionary).get("team", "")) != str(actor.get("team", ""))


func _save_result_valid(actor_id: int, value: Variant, saved_players: Array) -> bool:
	if not _save_action_valid(actor_id, value, saved_players):
		return false
	var result: Dictionary = value as Dictionary
	if result.get("status", "") not in ["success", "blocked", "trapped", "unknown", "passed", "no_effect"] or not result.get("message") is String:
		return false
	if result.has("candidates") and not _save_candidates_valid(result["candidates"]):
		return false
	return not result.has("visitor_count") or (result["visitor_count"] is int and int(result["visitor_count"]) >= 0 and int(result["visitor_count"]) <= 8)


func _save_state_valid(state: Dictionary, loaded_rules: Dictionary) -> bool:
	var dictionary_fields: Array[String] = ["votes", "actions", "blocked", "completed", "traps", "visits", "healed", "results", "bot_memory", "previous_vote_tally"]
	for field: String in dictionary_fields:
		if not state.get(field) is Dictionary or (state[field] as Dictionary).size() > 8:
			return false
	for field: String in ["players", "night_alive", "attacks", "reports", "statements"]:
		if not state.get(field) is Array:
			return false
	if state.get("phase", "") not in ["role_assignment", "night", "dawn", "discussion", "vote", "endgame"]:
		return false
	if not state.get("round_number") is int or int(state["round_number"]) < 0 or int(state["round_number"]) > 10000:
		return false
	if not state.get("winner") is String or state.get("winner", "") not in ["", "innocent", "impostor", "draw"] or ((state["phase"] == "endgame") != (state["winner"] != "")):
		return false
	for field: String in ["rng_seed", "rng_state"]:
		if not _save_integer_string_valid(state.get(field)):
			return false
	if not state.get("last_night_deaths") is int or int(state["last_night_deaths"]) < 0 or int(state["last_night_deaths"]) > 8:
		return false
	var saved_players: Array = state["players"] as Array
	if saved_players.size() != 8:
		return false
	var actual_deck: Dictionary = {}
	var configured_deck: Dictionary = {}
	for value: Variant in ((loaded_rules.get("first_deck", {}) as Dictionary).get("cards", []) as Array):
		var card: Dictionary = value as Dictionary
		var key: String = "%s:%s" % [str(card.get("team", "")), str(card.get("role", ""))]
		configured_deck[key] = int(configured_deck.get(key, 0)) + 1
	for id: int in range(8):
		if not saved_players[id] is Dictionary:
			return false
		var player: Dictionary = saved_players[id] as Dictionary
		if player.get("id", -1) != id or not player.get("id") is int or player.get("role", "") not in ROLE_NAMES or player.get("role", "") == "unknown" or player.get("team", "") not in ["innocent", "impostor"]:
			return false
		if not player.get("name") is String or not player.get("color") is String or not player.get("alive") is bool or not player.get("cleaned") is bool:
			return false
		var expected_apparent: String = "investigator" if str(player["role"]) == "insane" else str(player["role"])
		if player.get("apparent_role", "") != expected_apparent:
			return false
		if not _save_action_valid(id, {"kind": player.get("last_action"), "target": player.get("last_target")}, saved_players):
			return false
		if not player.get("notes") is Array or (player["notes"] as Array).size() > 10000 or not player.get("investigations") is Dictionary:
			return false
		for note: Variant in (player["notes"] as Array):
			if not note is String:
				return false
		for target: Variant in (player["investigations"] as Dictionary):
			var memory: Variant = (player["investigations"] as Dictionary)[target]
			if not _save_id(target) or not memory is Dictionary or not (memory as Dictionary).get("identity") is String or not _save_candidates_valid((memory as Dictionary).get("candidates")):
				return false
		var key: String = "%s:%s" % [str(player["team"]), str(player["role"])]
		actual_deck[key] = int(actual_deck.get(key, 0)) + 1
	if actual_deck != configured_deck or not _save_ids_valid(state["night_alive"], true) or not _save_ids_valid(state["attacks"]):
		return false
	for field: String in dictionary_fields:
		for key: Variant in (state[field] as Dictionary):
			if not _save_id(key):
				return false
			var value: Variant = (state[field] as Dictionary)[key]
			match field:
				"votes":
					if not _save_id(value, true) or int(value) == int(key):
						return false
				"actions":
					if not _save_action_valid(int(key), value, saved_players):
						return false
				"blocked", "completed", "healed":
					if not value is bool:
						return false
				"traps", "visits":
					if not _save_ids_valid(value):
						return false
				"results":
					if not _save_result_valid(int(key), value, saved_players):
						return false
				"previous_vote_tally":
					if not value is int or int(value) < 0 or int(value) > 8:
						return false
				"bot_memory":
					if not value is Dictionary:
						return false
					var bot: Dictionary = value as Dictionary
					if not bot.get("investigations") is Dictionary or not _save_ids_valid(bot.get("cleaned_targets")) or not _save_result_valid(int(key), bot.get("latest"), saved_players):
						return false
					for target: Variant in (bot["investigations"] as Dictionary):
						if not _save_id(target) or not _save_candidates_valid((bot["investigations"] as Dictionary)[target]):
							return false
	if (state["reports"] as Array).size() > 8 or (state["statements"] as Array).size() > 64:
		return false
	for value: Variant in (state["reports"] as Array):
		if not value is Dictionary:
			return false
		var report: Dictionary = value as Dictionary
		if not _save_id(report.get("actor")) or not _save_id(report.get("target")) or report.get("kind", "") not in ["investigate", "watch"] or not report.get("fictional") is bool:
			return false
	for value: Variant in (state["statements"] as Array):
		if not value is Dictionary:
			return false
		var statement: Dictionary = value as Dictionary
		if not _save_id(statement.get("actor")) or not _save_id(statement.get("target"), true) or statement.get("kind", "") not in ["accuse", "defend", "claim", "investigate", "watch", "block", "heal", "pass"] or not _save_candidates_valid(statement.get("candidates")):
			return false
		var kind: String = str(statement["kind"])
		if kind in ["claim", "pass"]:
			if int(statement["target"]) != -1:
				return false
		elif int(statement["target"]) < 0 or int(statement["target"]) == int(statement["actor"]):
			return false
		if (kind == "investigate") != ((statement["candidates"] as Array).size() == 2):
			return false
	var alive_ids: Array[int] = []
	var innocent_alive: int = 0
	var impostor_alive: int = 0
	for player_value: Variant in saved_players:
		var player: Dictionary = player_value as Dictionary
		if bool(player["alive"]):
			alive_ids.append(int(player["id"]))
			if str(player["team"]) == "impostor":
				impostor_alive += 1
			else:
				innocent_alive += 1
	if str(state["phase"]) == "role_assignment":
		if int(state["round_number"]) != 0 or alive_ids.size() != 8 or not (state["night_alive"] as Array).is_empty() or not (state["actions"] as Dictionary).is_empty() or not (state["votes"] as Dictionary).is_empty():
			return false
	elif int(state["round_number"]) == 0:
		return false
	if str(state["phase"]) == "night":
		var snapshot: Array = (state["night_alive"] as Array).duplicate()
		snapshot.sort()
		if snapshot != alive_ids:
			return false
		for actor_id: Variant in (state["actions"] as Dictionary):
			var action: Dictionary = (state["actions"] as Dictionary)[actor_id] as Dictionary
			if not alive_ids.has(actor_id) or (str(action["kind"]) != "pass" and not alive_ids.has(int(action["target"]))):
				return false
	if str(state["phase"]) == "endgame":
		var expected_winner: String = ""
		if alive_ids.is_empty():
			expected_winner = "draw"
		elif impostor_alive == 0:
			expected_winner = "innocent"
		elif impostor_alive >= innocent_alive:
			expected_winner = "impostor"
		if str(state["winner"]) != expected_winner:
			return false
	return true



func _save_integer_string_valid(value: Variant) -> bool:
	if not value is String:
		return false
	var raw: String = value as String
	if not raw.is_valid_int() or raw.begins_with("+") or raw == "-0":
		return false
	var negative: bool = raw.begins_with("-")
	var digits: String = raw.substr(1) if negative else raw
	if digits.is_empty() or (digits.length() > 1 and digits.begins_with("0")):
		return false
	var limit: String = "9223372036854775808" if negative else "9223372036854775807"
	return digits.length() < limit.length() or (digits.length() == limit.length() and digits <= limit)

