var HIGH = /[\uD800-\uDBFF]/;
var LOW = /[\uDC00-\uDFFF]/;
function at(value, caret) {
	return Math.max(0, Math.min(value.length, caret));
}
function before(value, caret) {
	if (caret <= 0) return 0;
	return caret > 1 && LOW.test(value.charAt(caret - 1)) && HIGH.test(value.charAt(caret - 2)) ? caret - 2 : caret - 1;
}
function after(value, caret) {
	if (caret >= value.length) return value.length;
	return HIGH.test(value.charAt(caret)) && LOW.test(value.charAt(caret + 1)) ? caret + 2 : caret + 1;
}
function lineStart(value, caret) {
	return value.lastIndexOf("\n", caret - 1) + 1;
}
function lineEnd(value, caret) {
	const next = value.indexOf("\n", caret);
	return next < 0 ? value.length : next;
}
function insertText(state, text, maxLength = -1) {
	const start = at(state.value, Math.min(state.start, state.end));
	const end = at(state.value, Math.max(state.start, state.end));
	let piece = text;
	if (maxLength >= 0) {
		const room = Math.max(0, maxLength - (state.value.length - (end - start)));
		const points = Array.from(piece);
		let kept = "";
		for (const point of points) {
			if (kept.length + point.length > room) break;
			kept += point;
		}
		piece = kept;
	}
	const value = state.value.slice(0, start) + piece + state.value.slice(end);
	const caret = start + piece.length;
	return {
		value,
		start: caret,
		end: caret
	};
}
function editKey(state, key, ctrl, shift, multiline) {
	const value = state.value;
	const start = at(value, Math.min(state.start, state.end));
	const end = at(value, Math.max(state.start, state.end));
	const collapsed = start === end;
	const move = (caret) => ({
		value,
		start: caret,
		end: caret
	});
	if (ctrl && (key === "a" || key === "A")) return {
		value,
		start: 0,
		end: value.length
	};
	if (ctrl) return null;
	switch (key) {
		case "Backspace": {
			const from = collapsed ? before(value, start) : start;
			return {
				value: value.slice(0, from) + value.slice(end),
				start: from,
				end: from
			};
		}
		case "Delete": {
			const to = collapsed ? after(value, end) : end;
			return {
				value: value.slice(0, start) + value.slice(to),
				start,
				end: start
			};
		}
		case "ArrowLeft":
			if (shift) return {
				value,
				start: before(value, start),
				end
			};
			return move(collapsed ? before(value, start) : start);
		case "ArrowRight":
			if (shift) return {
				value,
				start,
				end: after(value, end)
			};
			return move(collapsed ? after(value, end) : end);
		case "Home": {
			const target = multiline ? lineStart(value, start) : 0;
			return shift ? {
				value,
				start: target,
				end
			} : move(target);
		}
		case "End": {
			const target = multiline ? lineEnd(value, end) : value.length;
			return shift ? {
				value,
				start,
				end: target
			} : move(target);
		}
		case "ArrowUp": {
			if (!multiline) return shift ? {
				value,
				start: 0,
				end
			} : move(0);
			const head = lineStart(value, start);
			if (head === 0) return shift ? {
				value,
				start: 0,
				end
			} : move(0);
			const above = lineStart(value, head - 1);
			const target = Math.min(above + (start - head), head - 1);
			return shift ? {
				value,
				start: target,
				end
			} : move(target);
		}
		case "ArrowDown": {
			if (!multiline) return shift ? {
				value,
				start,
				end: value.length
			} : move(value.length);
			const tail = lineEnd(value, end);
			if (tail === value.length) return shift ? {
				value,
				start,
				end: value.length
			} : move(value.length);
			const column = end - lineStart(value, end);
			const target = Math.min(tail + 1 + column, lineEnd(value, tail + 1));
			return shift ? {
				value,
				start,
				end: target
			} : move(target);
		}
		case "Enter": return multiline ? insertText(state, "\n") : null;
		default: return null;
	}
}
function numberText(text) {
	return /^-?\d*(\.\d*)?$/.test(text);
}
function numberValue(text) {
	const trimmed = text.replace(/\.$/, "");
	return trimmed === "-" ? "" : trimmed;
}
var PROTOCOL = 1;
var SDK_VERSION = "1.0.1";
var HOST_ORIGIN = "https://cfx-nui-evolent_devices";
var STATE_TEXT = 512;
var KEY = /^[A-Za-z][A-Za-z0-9_]{0,23}$/;
var CONTROL = /[\u0000-\u001f\u007f]/;
function cleanFlatState(value) {
	if (!value || typeof value !== "object" || Array.isArray(value)) return null;
	const clean = {};
	let keys = 0;
	let bytes = 2;
	for (const [key, entry] of Object.entries(value)) {
		if (!KEY.test(key)) return null;
		keys += 1;
		if (keys > 16) return null;
		if (typeof entry === "number") {
			if (!Number.isFinite(entry)) return null;
			bytes += key.length + 24;
		} else if (typeof entry === "boolean") bytes += key.length + 8;
		else if (typeof entry === "string") {
			if (entry.length > STATE_TEXT || CONTROL.test(entry)) return null;
			bytes += key.length + new TextEncoder().encode(entry).length + 6;
		} else return null;
		clean[key] = entry;
	}
	return bytes <= 2048 ? clean : null;
}
var text = (value, max) => typeof value === "string" ? value.replace(/\s+/g, " ").trim().slice(0, max) : "";
function cleanNotice(value) {
	if (!value || typeof value !== "object") return null;
	const raw = value;
	const title = text(raw.title, 80);
	if (!title) return null;
	const notice = { title };
	const id = typeof raw.id === "number" ? String(raw.id) : text(raw.id, 64);
	if (id) notice.id = id;
	const body = text(raw.body, 240);
	if (body) notice.body = body;
	const action = text(raw.action, 32);
	if (action) notice.action = action;
	if (raw.intent && typeof raw.intent === "object" && !Array.isArray(raw.intent) && JSON.stringify(raw.intent).length <= 2048) notice.intent = raw.intent;
	if (typeof raw.at === "number" && Number.isFinite(raw.at)) notice.at = Math.floor(raw.at);
	return notice;
}
function cleanRecent(value) {
	if (!value || typeof value !== "object") return null;
	const raw = value;
	const title = text(raw.title, 60);
	if (!title) return null;
	const entry = { title };
	const sub = text(raw.sub, 60);
	if (sub) entry.sub = sub;
	if (raw.intent && typeof raw.intent === "object" && !Array.isArray(raw.intent) && JSON.stringify(raw.intent).length <= 2048) entry.intent = raw.intent;
	return entry;
}
var HELLO_TRIES = 8;
var HELLO_MS = 1e3;
var READY_TRIES = 5;
var READY_MS = 500;
var ACTIVITY_MS = 250;
var PUBLISH_MS = 500;
var DOUBLE_GUARD_MS = 400;
var POST_MS = 15e3;
var SHIM_ROW = 34;
var SHIM_MAX = 320;
var TEXT_TYPES = [
	"text",
	"search",
	"url",
	"tel",
	"password",
	"email",
	"number"
];
var FOCUSABLE = "input:not([type=hidden]):not([disabled]),textarea:not([disabled]),select:not([disabled]),button:not([disabled]),[tabindex]:not([tabindex=\"-1\"])";
var DIRECT_TYPES = new Set([
	"init",
	"open",
	"shown",
	"close",
	"watch",
	"state",
	"clock",
	"pointer",
	"idle",
	"deviceKey",
	"deviceDblClick",
	"osReply"
]);
var word = (value, pattern, limit) => (value ?? "").replace(pattern, "").slice(0, limit);
function initials(name) {
	return name.split(/\s+/).filter(Boolean).slice(0, 2).map((part) => Array.from(part)[0].toUpperCase()).join("");
}
function cleanUser(value) {
	if (!value || typeof value !== "object") return null;
	const raw = value;
	const name = typeof raw.name === "string" ? raw.name.slice(0, 64) : "";
	if (!name) return null;
	return {
		name,
		initials: typeof raw.initials === "string" && raw.initials ? raw.initials.slice(0, 4) : initials(name)
	};
}
var object = (value) => value && typeof value === "object" && !Array.isArray(value) ? value : {};
var finite = (value, fallback) => typeof value === "number" && Number.isFinite(value) ? value : fallback;
function cleanStudio(value) {
	if (!value || typeof value !== "object" || Array.isArray(value)) return null;
	const raw = value;
	const zoomMin = finite(raw.zoomMin, .8);
	const zoomMax = Math.max(zoomMin, finite(raw.zoomMax, 2));
	return {
		yaw: finite(raw.yaw, 0),
		pitch: finite(raw.pitch, 10),
		zoom: finite(raw.zoom, 1),
		zoomMin,
		zoomMax,
		spin: Math.max(0, finite(raw.spin, 0))
	};
}
var instance = null;
function connectApp(options = {}) {
	if (instance) return instance;
	const win = options.window ?? window;
	const realm = win;
	const doc = win.document;
	const send = options.fetch ?? win.fetch.bind(win);
	const params = new URLSearchParams(win.location.search);
	const hash = new URLSearchParams(win.location.hash.replace(/^#/, ""));
	const host = word(params.get("host"), /[^\w-]/g, 64);
	const harness = params.get("harness") === "1";
	const transport = win.parent !== win ? "frame" : host ? "direct" : "none";
	const hostOrigin = harness ? win.location.origin : HOST_ORIGIN;
	const mode = params.get("mode") === "watch" ? "watch" : transport === "none" ? "" : "use";
	const appId = word(params.get("app"), /[^a-z0-9_]/g, 32);
	const browser = word(params.get("browser"), /[^\w-]/g, 64);
	const secret = word(hash.get("s"), /[^0-9a-f]/gi, 64);
	const parentName = win.GetParentResourceName;
	const resource = typeof parentName === "function" ? String(parentName()) : /^cfx-nui-(.+)$/.exec(win.location.hostname)?.[1] ?? "";
	let kind = word(params.get("kind"), /[^a-z]/g, 16);
	let token = "";
	let context = {};
	let user = null;
	let locale = {};
	let brand = "Evolent OS";
	let scale = 1;
	let input = transport === "direct" ? "dui" : "native";
	let studio = null;
	let opened = false;
	let readySent = false;
	let relay = transport !== "none" && !resource;
	let helloTimer = null;
	let activityAt = 0;
	let pendingState = null;
	let publishTimer = null;
	let replyId = 0;
	const replies = new Map();
	const handlers = {
		action: new Map(),
		message: new Set(),
		open: new Set(),
		close: new Set(),
		intent: new Set(),
		visibility: new Set(),
		state: new Set()
	};
	const off = [];
	const listen = (target, type, handler, capture = false) => {
		target.addEventListener(type, handler, capture);
		off.push(() => target.removeEventListener(type, handler, capture));
	};
	const each = (set, value) => {
		for (const handler of [...set]) try {
			handler(value);
		} catch (error) {
			console.error("[evolent os app]", error);
		}
	};
	const add = (set, handler) => {
		set.add(handler);
		return () => {
			set.delete(handler);
		};
	};
	function toHost(type, extra = {}) {
		if (transport !== "frame") return;
		win.parent.postMessage({
			...extra,
			__os: 1,
			type,
			token
		}, hostOrigin);
	}
	function toGame(name, extra = {}) {
		if (transport !== "direct") return Promise.resolve(null);
		return send(`https://${host}/${name}`, {
			method: "POST",
			headers: { "Content-Type": "application/json; charset=UTF-8" },
			body: JSON.stringify({
				...extra,
				browser,
				s: secret
			})
		}).catch(() => null);
	}
	let field = null;
	let fieldValue = "";
	let shadow = null;
	let editing = null;
	let trustedDouble = -Infinity;
	let syntheticDouble = -Infinity;
	function fieldOf(target) {
		const element = target instanceof realm.Element ? target.closest("input,textarea") : null;
		if (element instanceof realm.HTMLTextAreaElement) return element.disabled || element.readOnly ? null : element;
		if (element instanceof realm.HTMLInputElement && TEXT_TYPES.includes(element.type) && !element.disabled && !element.readOnly) return element;
		return null;
	}
	function reportEditing() {
		const now = field !== null;
		if (editing === now) return;
		editing = now;
		if (mode !== "use") return;
		if (transport === "direct") toGame("device:state", { editing: now });
		else toHost("editing", { on: now });
	}
	function commit(target) {
		if (target.value === fieldValue) return;
		fieldValue = target.value;
		target.dispatchEvent(new realm.Event("change", { bubbles: true }));
	}
	function activate(next) {
		if (next === field) return;
		const previous = field;
		field = next;
		shadow = null;
		if (previous) {
			commit(previous);
			if (doc.activeElement === previous) previous.blur();
		}
		fieldValue = next ? next.value : "";
		if (next) next.focus({ preventScroll: true });
		reportEditing();
	}
	const onScreen = (element) => element.isConnected && element.getClientRects().length > 0;
	function liveField() {
		if (field && !onScreen(field)) activate(null);
		return field;
	}
	const isNumber = (target) => target instanceof realm.HTMLInputElement && target.type === "number";
	function selectionOf(target) {
		if (isNumber(target) && shadow !== null && numberValue(shadow) !== target.value) shadow = null;
		const value = isNumber(target) ? shadow ?? target.value : target.value;
		let start = null;
		let end = null;
		try {
			start = target.selectionStart;
			end = target.selectionEnd;
		} catch {
			start = null;
		}
		if (start === null || end === null || isNumber(target)) start = end = value.length;
		return {
			value,
			start,
			end
		};
	}
	function apply(target, next) {
		if (isNumber(target)) {
			if (!numberText(next.value)) return;
			shadow = next.value;
			const value = numberValue(next.value);
			if (target.value === value) return;
			target.value = value;
			target.dispatchEvent(new realm.Event("input", { bubbles: true }));
			return;
		}
		const changed = target.value !== next.value;
		if (changed) target.value = next.value;
		try {
			target.setSelectionRange(next.start, next.end);
		} catch {}
		if (changed) target.dispatchEvent(new realm.Event("input", { bubbles: true }));
	}
	function keyTarget() {
		const target = liveField();
		if (target) return target;
		const active = doc.activeElement;
		return active && active !== doc.body && active.isConnected ? active : doc.body;
	}
	function keyEvent(target, key, ctrl, shift) {
		const event = new realm.KeyboardEvent("keydown", {
			key,
			ctrlKey: ctrl,
			shiftKey: shift,
			bubbles: true,
			cancelable: true,
			composed: true
		});
		target.dispatchEvent(event);
		return !event.defaultPrevented;
	}
	function moveFocus(from, back) {
		const current = from ?? (doc.activeElement !== doc.body ? doc.activeElement : null);
		const scope = current?.closest("[role=\"dialog\"]") ?? doc;
		const list = Array.from(scope.querySelectorAll(FOCUSABLE)).filter((element) => element.getClientRects().length > 0);
		if (!list.length) return;
		const index = current ? list.indexOf(current) : -1;
		const next = list[index < 0 ? back ? list.length - 1 : 0 : (index + (back ? -1 : 1) + list.length) % list.length];
		const nextField = fieldOf(next);
		activate(nextField);
		if (!nextField) next.focus({ preventScroll: false });
	}
	function typeText(text) {
		const target = liveField();
		if (!target) {
			const at = keyTarget();
			for (const character of Array.from(text)) keyEvent(at, character, false, false);
			return;
		}
		apply(target, insertText(selectionOf(target), text, target.maxLength));
	}
	function unhandled(key, ctrl) {
		toHost("unhandled", {
			key,
			ctrl
		});
	}
	function controlKey(key, ctrl, shift) {
		if (shim.open && shimKey(key)) return;
		const target = liveField();
		if (!keyEvent(target ?? keyTarget(), key, ctrl, shift)) return;
		if (ctrl && key.toLowerCase() === "l") {
			unhandled("l", true);
			return;
		}
		if (key === "Tab") {
			moveFocus(target, shift);
			return;
		}
		if (key === "Escape") {
			if (target) activate(null);
			else unhandled("Escape", ctrl);
			return;
		}
		if (!target) return;
		const next = editKey(selectionOf(target), key, ctrl, shift, target instanceof realm.HTMLTextAreaElement);
		if (next) apply(target, next);
		else if (key === "Enter") commit(target);
	}
	function keyIn(message) {
		if (input !== "dui" || mode !== "use") return;
		if (message.kind === "text" && typeof message.text === "string") typeText(message.text);
		else if (message.kind === "key" && typeof message.key === "string") controlKey(message.key, message.ctrl === true, message.shift === true);
	}
	function doubleClick(x, y) {
		if (!Number.isFinite(x) || !Number.isFinite(y) || win.performance.now() - trustedDouble < DOUBLE_GUARD_MS) return;
		const target = doc.elementFromPoint(x, y);
		if (!target) return;
		syntheticDouble = win.performance.now();
		target.dispatchEvent(new realm.MouseEvent("dblclick", {
			bubbles: true,
			cancelable: true,
			composed: true,
			clientX: x,
			clientY: y,
			detail: 2,
			view: win
		}));
	}
	const shim = {
		open: false,
		index: -1,
		select: null,
		node: null
	};
	function closeShim() {
		shim.node?.remove();
		shim.open = false;
		shim.select = null;
		shim.node = null;
		shim.index = -1;
	}
	function markShim(index) {
		if (!shim.node) return;
		shim.index = index;
		Array.from(shim.node.children).forEach((child, position) => {
			const button = child;
			button.style.background = position === index ? "#17171f" : "transparent";
			button.style.color = button.disabled ? "#52525b" : position === index ? "#C3FF00" : "#e4e4e7";
		});
	}
	function pickShim(index) {
		const target = shim.select;
		closeShim();
		if (!target || !target.isConnected) return;
		const option = target.options[index];
		if (!option || option.disabled || target.selectedIndex === index) return;
		target.selectedIndex = index;
		target.dispatchEvent(new realm.Event("input", { bubbles: true }));
		target.dispatchEvent(new realm.Event("change", { bubbles: true }));
	}
	function stepShim(from, step) {
		const options = shim.select ? Array.from(shim.select.options) : [];
		for (let index = from + step; index >= 0 && index < options.length; index += step) if (!options[index].disabled) return index;
		return from;
	}
	function shimKey(key) {
		const count = shim.select ? shim.select.options.length : 0;
		if (key === "Escape" || key === "Tab") closeShim();
		else if (key === "ArrowDown") markShim(stepShim(shim.index, 1));
		else if (key === "ArrowUp") markShim(stepShim(shim.index, -1));
		else if (key === "Home") markShim(stepShim(-1, 1));
		else if (key === "End") markShim(stepShim(count, -1));
		else if (key === "Enter") pickShim(shim.index);
		return true;
	}
	function openShim(target) {
		const rect = target.getBoundingClientRect();
		const node = doc.createElement("div");
		node.setAttribute("role", "listbox");
		node.dataset.osShim = "1";
		const options = Array.from(target.options);
		const wanted = Math.min(options.length * SHIM_ROW + 12, SHIM_MAX);
		const below = win.innerHeight - rect.bottom;
		const above = below < wanted && rect.top > below;
		node.style.cssText = `position:fixed;z-index:2147483647;left:${rect.left}px;${above ? `bottom:${win.innerHeight - rect.top + 4}px` : `top:${rect.bottom + 4}px`};min-width:${rect.width}px;max-height:${SHIM_MAX}px;overflow-y:auto;display:flex;flex-direction:column;padding:6px;background:#0f0f15;border:1px solid #2a2a35;border-radius:8px;box-shadow:0 18px 50px rgba(0,0,0,.5);font:13px/1.3 Poppins,system-ui,sans-serif;box-sizing:border-box`;
		options.forEach((option, index) => {
			const button = doc.createElement("button");
			button.type = "button";
			button.textContent = option.label || option.text;
			button.disabled = option.disabled;
			button.style.cssText = "flex:0 0 auto;min-height:34px;padding:6px 12px;text-align:left;white-space:nowrap;border:0;border-radius:6px;cursor:pointer;font:inherit;background:transparent;color:#e4e4e7";
			button.addEventListener("pointerenter", () => !option.disabled && markShim(index));
			button.addEventListener("click", () => pickShim(index));
			node.appendChild(button);
		});
		doc.body.appendChild(node);
		shim.open = true;
		shim.select = target;
		shim.node = node;
		markShim(target.selectedIndex);
	}
	function pointerDown(event) {
		const target = event.target instanceof realm.Element ? event.target : null;
		if (target?.closest("[data-os-shim]")) return;
		const element = target?.closest("select");
		const reopen = element instanceof realm.HTMLSelectElement && shim.select !== element;
		closeShim();
		if (element instanceof realm.HTMLSelectElement) {
			event.preventDefault();
			if (input === "dui") activate(null);
			if (reopen && !element.disabled) openShim(element);
			return;
		}
		if (input === "dui") activate(fieldOf(target));
	}
	function activity() {
		const now = win.performance.now();
		if (now - activityAt < ACTIVITY_MS) return;
		activityAt = now;
		toHost("activity");
	}
	function nativeKey(event) {
		activity();
		if (input !== "native") return;
		const ctrl = event.ctrlKey || event.metaKey;
		if (shim.open && [
			"Escape",
			"Tab",
			"ArrowDown",
			"ArrowUp",
			"Home",
			"End",
			"Enter"
		].includes(event.key)) {
			event.preventDefault();
			shimKey(event.key);
			return;
		}
		if (ctrl && event.key.toLowerCase() === "l") {
			event.preventDefault();
			unhandled("l", true);
		} else if (event.key === "Escape" && !event.defaultPrevented) unhandled("Escape", ctrl);
	}
	function installInput() {
		listen(doc, "pointerdown", (event) => {
			activity();
			pointerDown(event);
		}, true);
		listen(doc, "mousedown", (event) => {
			if (event.target instanceof realm.Element && event.target.closest("select")) event.preventDefault();
		}, true);
		listen(win, "dblclick", (event) => {
			if (!event.isTrusted) return;
			if (win.performance.now() - syntheticDouble < DOUBLE_GUARD_MS) {
				event.stopImmediatePropagation();
				event.preventDefault();
				return;
			}
			trustedDouble = win.performance.now();
		}, true);
		listen(win, "contextmenu", (event) => event.preventDefault());
		listen(win, "wheel", activity, true);
		listen(win, "keydown", nativeKey);
		listen(win, "resize", closeShim);
	}
	function opening(raw, given) {
		context = object(given);
		user = cleanUser(raw.user) ?? user;
		if (raw.locale && typeof raw.locale === "object") locale = raw.locale;
		if (typeof raw.brand === "string") brand = raw.brand.slice(0, 40);
		if (typeof raw.kind === "string") kind = raw.kind.slice(0, 16);
		if (typeof raw.scale === "number" && raw.scale > 0) scale = raw.scale;
		if (raw.input === "dui" || raw.input === "native") input = raw.input;
		studio = transport === "direct" && mode === "use" ? cleanStudio(raw.studio) : null;
		opened = true;
		if (helloTimer) clearTimeout(helloTimer);
		helloTimer = null;
		doc.documentElement.dataset.osMode = mode || "page";
		each(handlers.open, {
			context,
			intent: raw.intent && typeof raw.intent === "object" ? raw.intent : null,
			user,
			kind,
			mode,
			scale,
			locale,
			brand,
			studio
		});
		if (raw.intent && typeof raw.intent === "object") each(handlers.intent, raw.intent);
		if (!options.manualReady) app.ready();
	}
	function own(message) {
		each(handlers.message, message);
		if (message && typeof message === "object" && typeof message.action === "string") {
			const set = handlers.action.get(message.action);
			if (set) for (const handler of [...set]) handler(message.data, message);
		}
	}
	function answer(id, data) {
		const key = String(id);
		const waiting = replies.get(key);
		if (!waiting) return;
		replies.delete(key);
		clearTimeout(waiting.timer);
		waiting.resolve(data ?? {
			ok: false,
			reason: "no_response"
		});
	}
	function fromHost(message) {
		switch (message.type) {
			case "os:open":
				if (typeof message.token !== "string") return;
				token = message.token;
				if (message.protocol !== 1) console.warn("[evolent os app] the host speaks protocol", message.protocol);
				opening(message, message.context);
				return;
			case "os:intent":
				each(handlers.intent, object(message.intent));
				return;
			case "os:visibility":
				each(handlers.visibility, message.visible === true);
				return;
			case "os:key":
				keyIn(message);
				return;
			case "os:dblclick":
				doubleClick(Number(message.x), Number(message.y));
				return;
			case "os:state": {
				const state = cleanFlatState(message.state);
				if (state) each(handlers.state, state);
				return;
			}
			case "os:close":
				closeShim();
				activate(null);
				each(handlers.close, typeof message.reason === "string" ? message.reason : "closed");
				return;
			case "os:reply":
				answer(message.id, message.data);
				return;
		}
	}
	function frameMessage(event) {
		if (event.source !== win.parent || event.origin !== hostOrigin) return;
		const message = event.data;
		if (!message || typeof message !== "object") return;
		if (message.__os === 1) {
			if (!opened && message.type !== "os:open") return;
			if (opened && message.token !== token) return;
			fromHost(message);
			return;
		}
		if (opened) own(message);
	}
	function directMessage(event) {
		if (event.source && event.source !== win) return;
		const message = event.data;
		if (!message || typeof message !== "object") return;
		if (secret && message.__s !== secret) return;
		if (DIRECT_TYPES.has(message.type)) switch (message.type) {
			case "init":
				if (message.locale && typeof message.locale === "object") locale = message.locale;
				break;
			case "open": {
				const given = object(message.app);
				token = typeof given.token === "string" ? given.token : "";
				opening(message, given.context);
				break;
			}
			case "watch":
				opening(message, object(object(message.extra).app).data);
				break;
			case "state": {
				const state = cleanFlatState(message.state);
				if (state) each(handlers.state, state);
				break;
			}
			case "close":
				closeShim();
				activate(null);
				each(handlers.close, "closed");
				break;
			case "deviceKey":
				keyIn(message);
				return;
			case "deviceDblClick":
				doubleClick(Number(message.x), Number(message.y));
				return;
			case "osReply":
				answer(message.id, message.data);
				return;
		}
		own(message);
	}
	function hello(attempt = 0) {
		if (opened || transport !== "frame") return;
		win.parent.postMessage({
			__os: 1,
			type: "hello",
			protocol: 1,
			sdk: SDK_VERSION,
			app: appId
		}, hostOrigin);
		if (attempt + 1 < HELLO_TRIES) helloTimer = setTimeout(() => hello(attempt + 1), HELLO_MS);
	}
	function deviceReady(attempt = 0) {
		toGame("device:ready", {
			width: win.innerWidth,
			height: win.innerHeight
		}).then((result) => {
			if (result === null && attempt + 1 < READY_TRIES) setTimeout(() => deviceReady(attempt + 1), READY_MS);
		});
	}
	function flushState() {
		publishTimer = null;
		if (!pendingState) return;
		const state = pendingState;
		pendingState = null;
		if (transport === "frame") toHost("publish", { state });
		else toGame("device:state", { state });
		publishTimer = setTimeout(flushState, PUBLISH_MS);
	}
	function relayPost(name, data, timeout) {
		return new Promise((resolve) => {
			const id = "p" + ++replyId;
			const timer = setTimeout(() => answer(id, {
				ok: false,
				reason: "no_response"
			}), timeout);
			replies.set(id, {
				resolve,
				timer
			});
			if (transport === "frame") toHost("post", {
				id,
				name,
				data: JSON.parse(JSON.stringify(data))
			});
			else toGame("os:post", {
				id,
				name,
				data,
				app: appId
			});
		});
	}
	async function postDirect(name, body, timeout) {
		const controller = new AbortController();
		const timer = setTimeout(() => controller.abort(), timeout);
		try {
			const text = await (await send(`https://${resource}/${name}`, {
				method: "POST",
				headers: { "Content-Type": "application/json; charset=UTF-8" },
				body: JSON.stringify(body),
				signal: controller.signal
			})).text();
			return text ? JSON.parse(text) : {};
		} finally {
			clearTimeout(timer);
		}
	}
	const app = {
		get hosted() {
			return transport !== "none";
		},
		get mode() {
			return mode;
		},
		get kind() {
			return kind;
		},
		get app() {
			return appId;
		},
		get transport() {
			return transport;
		},
		get input() {
			return input;
		},
		get token() {
			return token;
		},
		get context() {
			return context;
		},
		get user() {
			return user;
		},
		get locale() {
			return locale;
		},
		get brand() {
			return brand;
		},
		get scale() {
			return scale;
		},
		get opened() {
			return opened;
		},
		get relayed() {
			return relay;
		},
		get studio() {
			return studio;
		},
		on(action, handler) {
			let set = handlers.action.get(action);
			if (!set) handlers.action.set(action, set = new Set());
			return add(set, handler);
		},
		onMessage: (handler) => add(handlers.message, handler),
		onOpen(handler) {
			const stop = add(handlers.open, handler);
			if (opened) handler({
				context,
				intent: null,
				user,
				kind,
				mode,
				scale,
				locale,
				brand,
				studio
			});
			return stop;
		},
		onClose: (handler) => add(handlers.close, handler),
		onIntent: (handler) => add(handlers.intent, handler),
		onVisibility: (handler) => add(handlers.visibility, handler),
		onState: (handler) => add(handlers.state, handler),
		async post(name, data = {}, postOptions = {}) {
			if (!/^[\w:.-]{1,64}$/.test(name)) return {
				ok: false,
				reason: "bad_name"
			};
			if (mode === "watch" && !postOptions.readOnly) return {
				ok: false,
				reason: "watch_mode"
			};
			const timeout = postOptions.timeout ?? POST_MS;
			const body = token ? {
				...data,
				__os: token
			} : { ...data };
			if (transport === "none" || !relay) try {
				return await postDirect(name, body, timeout);
			} catch (error) {
				if (transport === "none" || error?.name === "AbortError") return {
					ok: false,
					reason: "no_response"
				};
				relay = true;
			}
			return relayPost(name, body, timeout);
		},
		publish(state) {
			if (mode !== "use" || transport === "none") return false;
			const clean = cleanFlatState(state);
			if (!clean) {
				console.warn("[evolent os app] publish takes at most 16 flat keys and 2 KB");
				return false;
			}
			pendingState = clean;
			if (!publishTimer) flushState();
			return true;
		},
		close() {
			if (mode !== "use") return;
			if (transport === "frame") toHost("close");
			else toGame("device:close");
		},
		leave() {
			if (mode !== "use") return;
			if (transport === "frame") toHost("leave");
			else toGame("device:close");
		},
		notify(notice) {
			const clean = cleanNotice(notice);
			if (!clean || mode !== "use" || transport !== "frame") return false;
			toHost("notify", { notice: clean });
			return true;
		},
		recent(entry) {
			const clean = cleanRecent(entry);
			if (!clean || mode !== "use" || transport !== "frame") return false;
			toHost("recent", { entry: clean });
			return true;
		},
		badge(count) {
			if (mode !== "use") return;
			toHost("badge", { count: Math.max(0, Math.min(999, Math.floor(Number(count) || 0))) });
		},
		privatePointer(on) {
			if (mode !== "use") return;
			if (transport === "frame") toHost("privatePointer", { on: on === true });
			else toGame("device:state", { privatePointer: on === true });
		},
		studioSend(action) {
			if (mode !== "use" || transport !== "direct" || !studio || !action || typeof action.act !== "string") return false;
			toGame("device:studio", { ...action });
			return true;
		},
		ready() {
			if (readySent || !opened) return;
			readySent = true;
			toHost("ready");
		},
		disconnect() {
			for (const stop of off.splice(0)) stop();
			if (helloTimer) clearTimeout(helloTimer);
			if (publishTimer) clearTimeout(publishTimer);
			for (const [id] of replies) answer(id, {
				ok: false,
				reason: "disconnected"
			});
			closeShim();
			instance = null;
		}
	};
	if (transport === "frame") {
		listen(win, "message", frameMessage);
		installInput();
		hello();
	} else if (transport === "direct") {
		listen(win, "message", directMessage);
		installInput();
		win.requestAnimationFrame(() => win.requestAnimationFrame(() => deviceReady()));
	}
	instance = app;
	return app;
}
export { PROTOCOL, SDK_VERSION, cleanFlatState, connectApp };
