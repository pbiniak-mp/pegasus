import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import ask from '@salesforce/apex/AiChatController.ask';

const MAX_TEXTAREA_HEIGHT = 160;
const SUGGESTIONS = [
	'How many leads were created today?',
	'Which 5 open opportunities have the largest amount?',
	'List my accounts in the Technology industry.'
];

// --- Minimal, safe Markdown -> HTML -------------------------------------------
// All text is HTML-escaped first; we only ever emit a fixed, attribute-free set
// of tags (strong/em/code/ul/ol/li/table/.../p/br/h1-6) plus internal record
// links (<a data-id> for Salesforce Ids only). No external links, no raw HTML,
// so the result is safe to inject into a lwc:dom="manual" node.

function escapeHtml(text) {
	return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function inlineFormat(text) {
	let out = escapeHtml(text);
	out = out.replace(/`([^`]+)`/g, '<code>$1</code>');
	// [label](recordId) -> internal record link, only when the target is a Salesforce Id.
	out = out.replace(/\[([^\]]+)\]\(([^)]+)\)/g, (match, label, target) => {
		const id = target.trim();
		if (/^[a-zA-Z0-9]{15}(?:[a-zA-Z0-9]{3})?$/.test(id)) {
			return '<a class="rec-link" data-id="' + id + '" tabindex="0">' + label + '</a>';
		}
		return label;
	});
	out = out.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
	out = out.replace(/\*([^*]+)\*/g, '<em>$1</em>');
	return out;
}

function isTableSeparator(line) {
	const t = line.trim();
	return t.includes('-') && t.includes('|') && /^[\s|:-]+$/.test(t);
}

function splitRow(line) {
	let s = line.trim();
	if (s.startsWith('|')) {
		s = s.slice(1);
	}
	if (s.endsWith('|')) {
		s = s.slice(0, -1);
	}
	return s.split('|').map((c) => c.trim());
}

function mdToHtml(md) {
	if (!md) {
		return '';
	}
	const lines = md.replace(/\r\n?/g, '\n').split('\n');
	const out = [];
	let i = 0;

	while (i < lines.length) {
		const line = lines[i];

		if (line.trim() === '') {
			i++;
			continue;
		}

		// Pipe table: header row immediately followed by a separator row.
		if (line.includes('|') && i + 1 < lines.length && isTableSeparator(lines[i + 1])) {
			const header = splitRow(line);
			let j = i + 2;
			let body = '';
			while (j < lines.length && lines[j].includes('|') && lines[j].trim() !== '') {
				const cells = splitRow(lines[j]);
				let row = '<tr>';
				for (let k = 0; k < header.length; k++) {
					row += '<td>' + inlineFormat(cells[k] != null ? cells[k] : '') + '</td>';
				}
				body += row + '</tr>';
				j++;
			}
			let head = '<tr>';
			header.forEach((c) => {
				head += '<th>' + inlineFormat(c) + '</th>';
			});
			out.push('<table><thead>' + head + '</tr></thead><tbody>' + body + '</tbody></table>');
			i = j;
			continue;
		}

		// Heading
		const heading = line.match(/^(#{1,6})\s+(.*)$/);
		if (heading) {
			const lvl = Math.min(heading[1].length, 6);
			out.push('<h' + lvl + '>' + inlineFormat(heading[2]) + '</h' + lvl + '>');
			i++;
			continue;
		}

		// Unordered list
		if (/^\s*[-*+]\s+/.test(line)) {
			let items = '';
			while (i < lines.length && /^\s*[-*+]\s+/.test(lines[i])) {
				items += '<li>' + inlineFormat(lines[i].replace(/^\s*[-*+]\s+/, '')) + '</li>';
				i++;
			}
			out.push('<ul>' + items + '</ul>');
			continue;
		}

		// Ordered list
		if (/^\s*\d+\.\s+/.test(line)) {
			let items = '';
			while (i < lines.length && /^\s*\d+\.\s+/.test(lines[i])) {
				items += '<li>' + inlineFormat(lines[i].replace(/^\s*\d+\.\s+/, '')) + '</li>';
				i++;
			}
			out.push('<ol>' + items + '</ol>');
			continue;
		}

		// Paragraph (collect consecutive lines until the next block boundary).
		const para = [];
		while (
			i < lines.length &&
			lines[i].trim() !== '' &&
			!/^\s*[-*+]\s+/.test(lines[i]) &&
			!/^\s*\d+\.\s+/.test(lines[i]) &&
			!/^#{1,6}\s+/.test(lines[i]) &&
			!(lines[i].includes('|') && i + 1 < lines.length && isTableSeparator(lines[i + 1]))
		) {
			para.push(inlineFormat(lines[i]));
			i++;
		}
		out.push('<p>' + para.join('<br>') + '</p>');
	}

	return out.join('');
}

// -----------------------------------------------------------------------------

export default class AiChat extends NavigationMixin(LightningElement) {
	messages = [];
	draft = '';
	isLoading = false;
	suggestions = SUGGESTIONS;
	_seq = 0;
	_renderedIds = new Set();

	get isEmpty() {
		return this.messages.length === 0;
	}

	get isSendDisabled() {
		return this.isLoading || !this.draft || !this.draft.trim();
	}

	get isClearDisabled() {
		return this.isLoading || this.messages.length === 0;
	}

	// Inject rendered HTML for assistant bubbles once per message.
	renderedCallback() {
		this.template.querySelectorAll('div.rich').forEach((node) => {
			const id = Number(node.dataset.id);
			if (this._renderedIds.has(id)) {
				return;
			}
			const msg = this.messages.find((m) => m.id === id);
			if (msg && msg.html != null) {
				node.innerHTML = msg.html;
				this._renderedIds.add(id);
			}
		});
	}

	handleInput(event) {
		this.draft = event.target.value;
		this.autoGrow(event.target);
	}

	handleKeyDown(event) {
		// Enter sends; Shift+Enter inserts a newline.
		if (event.key === 'Enter' && !event.shiftKey) {
			event.preventDefault();
			this.send();
		}
	}

	handleSendClick() {
		this.send();
	}

	handleSuggestion(event) {
		this.send(event.currentTarget.dataset.q);
	}

	// Delegated click handler for record links rendered inside assistant bubbles.
	handleMessagesClick(event) {
		const link = event.target && event.target.closest ? event.target.closest('a.rec-link') : null;
		if (!link) {
			return;
		}
		event.preventDefault();
		const recordId = link.dataset.id;
		if (recordId) {
			this[NavigationMixin.Navigate]({
				type: 'standard__recordPage',
				attributes: { recordId, actionName: 'view' }
			});
		}
	}

	handleClear() {
		this.messages = [];
		this._renderedIds.clear();
		this.draft = '';
		this.resetInput();
	}

	async send(presetQuestion) {
		const text = (presetQuestion != null ? presetQuestion : this.draft || '').trim();
		if (!text || this.isLoading) {
			return;
		}

		// Capture prior turns before adding the new question. Sent as a JSON
		// string — a List<ChatTurn> param passed directly from LWC arrives empty
		// in Apex, so we serialize here and deserialize on the server.
		const history = JSON.stringify(this.messages.map((m) => ({ role: m.role, text: m.text })));

		this.appendMessage('user', text);
		this.draft = '';
		this.resetInput();
		this.isLoading = true;
		this.scrollToBottom();

		try {
			const result = await ask({ question: text, history });
			this.appendMessage('assistant', result.isError ? result.errorMessage : result.answer);
		} catch (error) {
			const message =
				(error && error.body && error.body.message) ||
				(error && error.message) ||
				'Unexpected error.';
			this.appendMessage('assistant', message);
		} finally {
			this.isLoading = false;
			this.scrollToBottom();
		}
	}

	appendMessage(role, text) {
		const isUser = role === 'user';
		this.messages = [
			...this.messages,
			{
				id: ++this._seq,
				role,
				isUser,
				text,
				html: isUser ? null : mdToHtml(text),
				time: this.nowTime(),
				rowClass: isUser ? 'row row-user' : 'row row-assistant',
				wrapClass: isUser ? 'wrap wrap-user' : 'wrap wrap-assistant',
				bubbleClass: isUser ? 'bubble bubble-user' : 'bubble bubble-assistant'
			}
		];
	}

	nowTime() {
		return new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
	}

	autoGrow(el) {
		if (!el) {
			return;
		}
		el.style.height = 'auto';
		el.style.height = Math.min(el.scrollHeight, MAX_TEXTAREA_HEIGHT) + 'px';
	}

	resetInput() {
		const el = this.refs.input;
		if (el) {
			el.value = '';
			el.style.height = 'auto';
		}
	}

	scrollToBottom() {
		// eslint-disable-next-line @lwc/lwc/no-async-operation
		window.requestAnimationFrame(() => {
			const list = this.refs.messages;
			if (list) {
				list.scrollTop = list.scrollHeight;
			}
		});
	}
}
