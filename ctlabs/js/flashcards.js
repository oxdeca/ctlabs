/*
 -----------------------------------------------------------------------------
 File        : ctlabs/public/js/flashcards.js
 License     : MIT License
 -----------------------------------------------------------------------------
*/

const VERSION_DATE    = "2026-02-15";
const VERSION_COUNTER = "121";
const VERSION         = `v${VERSION_DATE}-${VERSION_COUNTER}`;

function getISOString(d = new Date()) {
  const pad = (n) => n.toString().padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
}
function convertTo24h(str) {
  if (!str) return getISOString();
  const d = new Date(str);
  if (isNaN(d.getTime())) return str;
  return getISOString(d);
}

class Answer {
  constructor(id, txt, type = "false") {
    this.id = id;
    this.txt = txt;
    this.type = type;
  }
}
class Card {
  constructor(id, question, answers = [], info = "") {
    this.id = id || Date.now();
    this.question = question;
    this.info = info;
    this.isDraft = false;
    const hasIds = answers.some(a => a.id !== undefined && a.id !== null);
    if (!hasIds) {
      this.answers = answers.map((a, i) => new Answer(i + 1, a.txt, a.type));
    } else {
      const existingIds = answers.map(a => a.id).filter(x => x !== undefined && x !== null);
      let maxId = existingIds.length > 0 ? Math.max(...existingIds) : 0;
      this.answers = answers.map(a => {
        let aid = a.id;
        if (aid === undefined || aid === null) aid = ++maxId;
        return new Answer(aid, a.txt, a.type);
      });
    }
  }
}

class CardSet {
  constructor(name = "New Set", filename = "Direct Entry") {
    this.meta = {
      name: name,
      created: getISOString(),
      modified: getISOString(),
      filename: filename,
      loadedAt: getISOString()
    };
    this.cards = [];
    this.index = 0;
  }
}

class FlashCardsView {
  constructor() {
    this.marked = marked;
    this.marked.use({ gfm: true, breaks: true, headerIds: false, mangle: false });
    this.previewStates = { q: false, ans: false, info: false };
  }
  autoExpand(el) {
    if (!el) return;
    el.style.height = 'auto';
    el.style.height = (el.scrollHeight) + 'px';
  }
  highlightCode(container) {
    if (!container || !window.hljs) return;
    container.querySelectorAll('pre code').forEach(block => {
      hljs.highlightElement(block);
    });
  }
  updateStatus(index, total, isQuiz, isEdit) {
    document.getElementById('progress-bar').style.width = total > 0 ? ((index + 1) / total * 100) + "%" : "0%";
    document.getElementById('counter').innerText = total > 0 ? `${index + 1} / ${total}` : "0 / 0";
    const btnMain = document.getElementById('btn-main');
    if(!isEdit) btnMain.className = "w3-button w3-blue";
    
    document.querySelectorAll('.admin-tool').forEach(btn => {
      const alwaysActive = ['btn-add', 'btn-import', 'btn-newset', 'btn-raw'];
      btn.disabled = (total === 0 && !alwaysActive.includes(btn.id)) || isQuiz || isEdit;
    });
    document.getElementById('btn-prev').disabled = (total === 0 || isEdit || isQuiz);
    document.getElementById('btn-quiz').disabled = (total === 0 || isEdit);
    document.getElementById('btn-quiz').classList.toggle('quiz-active', isQuiz);
    document.getElementById('quiz-timer').style.display = isQuiz ? 'block' : 'none';
    document.getElementById('btn-stats').style.display = isQuiz ? 'block' : 'none';
  }
  renderStudy(card, isQuiz, isAnswered) {
    document.getElementById('display-area').style.display = 'block';
    document.getElementById('qfooter').style.display = 'flex';
    document.querySelectorAll('.results-screen').forEach(r => r.remove());
    const oldCancel = document.getElementById('btn-cancel'); if(oldCancel) oldCancel.remove();
    const header = document.getElementById('qheader');
    const container = document.getElementById('panswers');
    const infoBox = document.getElementById('cinfo');
    infoBox.style.display = 'none';
    if (!card) {
      header.innerHTML = "<div class='w3-center' style='width:100%'>No cardset loaded.</div>";
      container.innerHTML = "";
      return;
    }
    header.innerHTML = `<div class="w3-container">${this.marked.parse(card.question)}</div>`;
    this.highlightCode(header);
    container.innerHTML = "";
    const displayAnswers = (
      this.controller?.shuffledAnswersCache?.cardId === card.id
      ? this.controller.shuffledAnswersCache.answers
      : card.answers
    );
    displayAnswers.forEach((ans, displayIndex) => {
      if (!ans.txt) return;
      const div = document.createElement('div');
      div.className = "ans-row-container w3-cell-row";
      div.innerHTML = `
      <div class="w3-cell ans-id-badge" title="Position: ${displayIndex + 1} | Answer ID: ${ans.id}">
      ${displayIndex + 1}
      </div>
      <div class="w3-cell" style="width:20px">
      <input type="checkbox" id="ans-chk-${displayIndex}" class="w3-check" data-real-id="${ans.id}" ${isAnswered ? 'disabled' : ''}>
      </div>
      <div class="w3-cell ans-text-cell">
      ${this.marked.parse(ans.txt).replace(/<p>/g,'').replace(/<\/p>/g,'')}
      </div>`;
      div.onclick = (e) => {
        const cb = div.querySelector('input');
        if(cb.disabled) return;
        if(e.target.tagName !== 'A' && e.target !== cb && e.target.tagName !== 'CODE' && e.target.tagName !== 'PRE') {
          cb.checked = !cb.checked;
        }
      };
      container.appendChild(div);
    });
    this.highlightCode(container);
    const btnMain = document.getElementById('btn-main');
    btnMain.innerText = "Check";
    btnMain.disabled = isAnswered;
    document.getElementById('btn-next').disabled = (isQuiz && !isAnswered);
  }
  showFeedback(card, results, infoText) {
    results.forEach(res => {
      const row = document.querySelector(`#ans-chk-${res.index}`).closest('.ans-row-container');
      if (res.checked && res.type === "true") row.classList.add("w3-green");
      else if (res.checked && res.type === "false") row.classList.add("w3-red");
      else if (!res.checked && res.type === "true") row.classList.add("w3-red");
    });
    if (infoText) {
      const infoBox = document.getElementById('cinfo');
      infoBox.innerHTML = `<div class="w3-container">${this.marked.parse(infoText)}</div>`;
      this.highlightCode(infoBox);
      infoBox.style.display = 'block';
    }
    document.getElementById('btn-main').disabled = true;
  }
  renderEdit(card) {
    const infoBox = document.getElementById('cinfo');
    infoBox.style.display = 'none';
    infoBox.innerHTML = '';
    document.getElementById('btn-next').disabled = true;
    document.getElementById('btn-prev').disabled = true;
    const btnMain = document.getElementById('btn-main');
    btnMain.innerText = "Save";
    btnMain.className = "w3-button w3-green";
    btnMain.disabled = false;
    const footer = document.getElementById('ccard');
    if(!document.getElementById('btn-cancel')) {
      const cancel = document.createElement('button'); cancel.id = "btn-cancel"; cancel.innerText = "Cancel Edit";
      cancel.onclick = () => app.cancelEdit();
      footer.appendChild(cancel);
    }
    document.getElementById('qheader').innerHTML = `<textarea id="edit-q" class="w3-input" rows="1" placeholder="Question">${card.question}</textarea>`;
    const qClass = this.previewStates.q ? '' : 'collapsed';
    const ansClass = this.previewStates.ans ? '' : 'collapsed';
    const infoClass = this.previewStates.info ? '' : 'collapsed';
    const container = document.getElementById('panswers');
    container.innerHTML = `
    <div id="panel-q" class="preview-panel ${qClass}"><div class="preview-header" onclick="app.togglePreview('q')"><span class="preview-label">Preview Question</span><i class="fa fa-chevron-down preview-toggle-icon"></i></div><div id="preview-q-box" class="preview-box"></div></div>
    <div id="edit-rows-container"></div>
    <div class="w3-center w3-padding"><button class="w3-button" onclick="app.addAnswerRow()"><i class="fa fa-plus-circle btn-blue w3-xlarge"></i></button></div>
    <div id="panel-ans" class="preview-panel ${ansClass}"><div class="preview-header" onclick="app.togglePreview('ans')"><span class="preview-label">Preview Answers</span><i class="fa fa-chevron-down preview-toggle-icon"></i></div><div id="preview-ans-box" class="preview-box"></div></div>
    <div style="margin-top:25px;"><textarea id="edit-info" class="w3-input" rows="1" placeholder="Info/Hint (Use \${answer1} for dynamic text)" >${card.info}</textarea></div>
    <div id="panel-info" class="preview-panel ${infoClass}"><div class="preview-header" onclick="app.togglePreview('info')"><span class="preview-label">Preview Info</span><i class="fa fa-chevron-down preview-toggle-icon"></i></div><div id="preview-i-box" class="preview-box"></div></div>`;
    const rowContainer = document.getElementById('edit-rows-container');
    card.answers.forEach((ans, i) => {
      rowContainer.insertAdjacentHTML('beforeend', `
      <div class="ans-row-container w3-cell-row edit-row">
      <div class="w3-cell ans-id-badge" title="ID: ${ans.id}">${ans.id}</div>
      <div class="w3-cell" style="width:20px">
      <input type="checkbox" id="edit-type-${i}" class="w3-check" ${ans.type === "true" ? "checked" : ""}>
      </div>
      <div class="w3-cell ans-text-cell">
      <textarea class="w3-input" id="edit-txt-${i}" data-id="${ans.id}" rows="1" placeholder="Choice">${ans.txt}</textarea>
      </div>
      <div class="w3-cell" style="width:40px; text-align:right;">
      <button class="w3-button" onclick="app.removeRow(${ans.id})"><i class="fa fa-trash btn-red"></i></button>
      </div>
      </div>`);
    });
    setTimeout(() => { document.querySelectorAll('textarea.w3-input').forEach(tx => {
      tx.oninput = () => this.autoExpand(tx);
      this.autoExpand(tx);
    }); }, 0);
    document.getElementById('edit-q').addEventListener('input', () => this.updatePreviews());
    document.getElementById('edit-info').addEventListener('input', () => this.updatePreviews());
    document.querySelectorAll('textarea[id^="edit-txt-"]').forEach(el => { el.addEventListener('input', () => this.updatePreviews()); });
    this.updatePreviews();
  }
  updatePreviews() {
    const qText = document.getElementById('edit-q').value;
    const qBox = document.getElementById('preview-q-box');
    qBox.innerHTML = this.marked.parse(qText || "_No question_");
    this.highlightCode(qBox);
    let iText = document.getElementById('edit-info').value || "_No info_";
    iText = iText.replace(/\$\{\s*answer\s*(\d+)\s*\}/gi, (match, idStr) => {
      const id = parseInt(idStr, 10);
      const input = document.querySelector(`textarea[data-id="${id}"]`);
      return input ? input.value : match;
    });
    const iBox = document.getElementById('preview-i-box');
    iBox.innerHTML = this.marked.parse(iText);
    this.highlightCode(iBox);
    const ansBox = document.getElementById('preview-ans-box');
    ansBox.innerHTML = "";
    document.querySelectorAll('.edit-row').forEach(row => {
      const txt = row.querySelector('textarea').value;
      if(txt.trim()) ansBox.insertAdjacentHTML('beforeend', `<div class="preview-answer-item w3-container">${this.marked.parse(txt)}</div>`);
    });
    this.highlightCode(ansBox);
  }
  togglePreviewClass(key) {
    this.previewStates[key] = !this.previewStates[key];
    const panel = document.getElementById(`panel-${key}`);
    panel.classList.toggle('collapsed');
    this.updatePreviews();
  }
  renderResults(correct, total, chartHTML, title = "Results", subtext = "") {
    document.getElementById('display-area').style.display = 'none';
    document.getElementById('qfooter').style.display = 'none';
    const pct = total > 0 ? Math.round((correct/total)*100) : 0;
    document.getElementById('ccard').insertAdjacentHTML('afterbegin', `
    <div class="results-screen">
    <h2>${title}</h2>
    <div style="font-size:3.5em; font-weight:bold; color:var(--primary)">${pct}%</div>
    ${chartHTML}
    <div class="w3-center w3-padding w3-text-grey">${subtext}</div>
    <div class="w3-padding-16">
    <button class="w3-button w3-blue w3-round" onclick="app.restartQuiz()">Restart</button>
    <button class="w3-button w3-blue w3-round w3-margin-left" onclick="app.exitQuiz()">Exit</button>
    </div>
    </div>`);
  }
  showModal(title, bodyHTML, footerHTML = null) {
    document.getElementById('modal-title').innerText = title;
    document.getElementById('modal-body').innerHTML = bodyHTML;
    const footer = document.getElementById('modal-footer');
    if(footerHTML) { footer.innerHTML = footerHTML; footer.style.display = 'block'; }
    else { footer.style.display = 'none'; }
    document.getElementById('modal-container').style.display = 'flex';
    this.highlightCode(document.getElementById('modal-body'));
  }
  closeModal() { document.getElementById('modal-container').style.display = 'none'; }
}

class FlashCardsController {
  constructor(view) {
    this.view                 = view;
    this.cardset              = new CardSet();
    this.isEditing            = false;
    this.isQuiz               = false;
    this.quizScores           = [];
    this.timer                = { seconds: 0, interval: null };
    this.readOnly             = document.getElementById('flashcards-container').dataset.readOnly === "true";  //"<%= @read_only %>" === "true";
    this.editBuffer           = null;
    this.autoSaveTimer        = null;
    this.serverDataLoaded     = false;
    this.shuffledAnswersCache = [];
    this.init();
  }

  init() {
    const container = document.getElementById('flashcards-container');
    document.getElementById('file-input').onchange = (e) => this.handleFileImport(e);
    this.loadFromServer().then((serverLoaded) => {
      this.serverDataLoaded = serverLoaded;
      if(!serverLoaded) {
        this.loadSession();
      }
      this.update();
      this.setupAutoSave();
     });
  }

  async loadFromServer() {
    try {
      const res = await fetch('/flashcards.json?t=' + new Date().getTime());
      if (this.readOnly) {
          document.getElementById('flashcards-container').classList.add('readonly-mode');
      }
      
      if (res.ok) {
        const rawData = await res.json();
        const data = rawData.set ? rawData : { set: rawData };
        if (data.set && data.set.cards && data.set.cards.length > 0) {
          this.cardset        = new CardSet(data.set.meta.name, data.set.meta.filename);
          this.cardset.meta   = data.set.meta;
          this.cardset.cards  = data.set.cards.map(c => new Card(c.id, c.question, c.answers, c.info));
          this.cardset.index  = data.set.index || 0;
          return true;
        }
      }
    } catch(e) {
      console.warn('Server load failed (File might be empty):', e);
    }
    return false;
  }

  async saveToServer() {
    if (this.readOnly) return;
    if (!this.cardset || this.cardset.cards.length === 0) return;

    try {
      const data = { set: this.cardset, version: VERSION };
      const res = await fetch('/flashcards/data', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data)
      });
      if (res.status === 403) {
        this.readOnly = true;
        location.reload(); 
        return;
      }
    } catch(e) {
      console.warn('Server save failed:', e);
    }
  }

  setupAutoSave() {
    if (this.cardset.cards.length > 0 && !this.readOnly) {
      this.saveToServer();
    }
    this.originalSaveSession = this.saveSession.bind(this);
    this.saveSession = () => {
      this.originalSaveSession();
      clearTimeout(this.autoSaveTimer);
      this.autoSaveTimer = setTimeout(() => {
        this.saveToServer();
      }, 2000);
    };
  }

  saveSession() { localStorage.setItem('flashcards_mvc_session', JSON.stringify({ set: this.cardset })); }
  
  loadSession() {
    const stored = localStorage.getItem('flashcards_mvc_session');
    if (stored) {
      try {
        const data = JSON.parse(stored);
        this.cardset = new CardSet(data.set.meta.name, data.set.meta.filename);
        this.cardset.meta = data.set.meta;
        this.cardset.meta.loadedAt = getISOString();
        this.cardset.cards = data.set.cards.map(c => new Card(c.id, c.question, c.answers, c.info));
        this.cardset.index = data.set.index || 0;
      } catch(e) { console.error(e); }
    }
  }

  clearCache() {
    if(this.readOnly) {
      alert('Cannot clear cache in read-only mode');
      return;
    }
    if(confirm("Clear local cache? Server data preserved.")) {
      localStorage.removeItem('flashcards_mvc_session');
      this.loadFromServer().then(() => {
        this.update();
      });
    }
  }

  update() {
    const total = this.cardset.cards.length;
    if (this.cardset.index >= total && total > 0) this.cardset.index = 0;
    const card = total > 0 ? this.cardset.cards[this.cardset.index] : null;
    this.view.updateStatus(this.cardset.index, total, this.isQuiz, this.isEditing);
    if (this.isEditing && this.editBuffer) {
      this.view.renderEdit(this.editBuffer);
    } else if (card) {
      const isAnswered = this.isQuiz ? (this.quizScores[this.cardset.index] !== undefined) : false;
      if (!this.shuffledAnswersCache || this.shuffledAnswersCache.cardId !== card.id) {
        const shuffled = [...card.answers].sort(() => Math.random() - 0.5);
        this.shuffledAnswersCache = { cardId: card.id, answers: shuffled };
      }
      const renderCard = new Card(card.id, card.question, this.shuffledAnswersCache.answers, card.info);
      this.view.renderStudy(renderCard, this.isQuiz, isAnswered);
      if(isAnswered) this.check(true);
    } else {
      this.view.renderStudy(null, false, false);
    }
  }

  handleAction() { if (this.isEditing) this.saveCard(); else this.check(); }
  
  check(isReplay = false) {
    const card = this.cardset.cards[this.cardset.index];
    const visualAnswers = this.shuffledAnswersCache.answers;
    let perfect = true;
    const resultStates = [];
    visualAnswers.forEach((ans, i) => {
      const cb = document.getElementById(`ans-chk-${i}`);
      if(!cb) return;
      cb.disabled = true;
      const checked = cb.checked;
      if (checked && ans.type === "false") perfect = false;
      if (!checked && ans.type === "true") perfect = false;
      resultStates.push({ index: i, checked: checked, type: ans.type });
    });
    if (this.isQuiz && !isReplay) {
      this.quizScores[this.cardset.index] = perfect;
      if(this.cardset.index < this.cardset.cards.length) document.getElementById('btn-next').disabled = false;
    }
    let expandedInfo = card.info || "";
    if (expandedInfo) {
      const positionMap = new Map();
      this.shuffledAnswersCache.answers.forEach((ans, idx) => {
        positionMap.set(ans.id, idx);
      });
      expandedInfo = expandedInfo.replace(/\$\{\s*answer[:]?\s*(\d+)(?:\s*\|\s*(\d+))?\s*\}/gi, (match, idStr, lenStr) => {
        const id = parseInt(idStr, 10);
        const targetAnswer = card.answers.find(a => a.id === id);
        if (!targetAnswer) return match;
        let text = targetAnswer.txt;
        if (lenStr) {
          const maxLength = parseInt(lenStr, 10);
          if (text.length > maxLength) {
            text = text.substring(0, maxLength) + '...';
          }
        }
        return text;
      });
      expandedInfo = expandedInfo.replace(/\$\{\s*idx[:]?\s*(\d+)\s*\}/gi, (match, idStr) => {
        const id = parseInt(idStr, 10);
        const shuffledIndex = positionMap.get(id);
        if (shuffledIndex !== undefined) {
          const displayNumber = shuffledIndex + 1;
          return `<span class="ans-id-badge">${displayNumber}</span>`;
        }
        return match;
      });
    }
    this.view.showFeedback(card, resultStates, expandedInfo);
  }

  next() {
    if (this.isQuiz && this.cardset.index === this.cardset.cards.length - 1) {
      this.showQuizResults();
    } else {
      this.cardset.index = (this.cardset.index + 1) % this.cardset.cards.length;
      this.shuffledAnswersCache = null;
      this.update();
    }
  }

  prev() {
    this.cardset.index = (this.cardset.index === 0) ? this.cardset.cards.length - 1 : this.cardset.index - 1;
    this.shuffledAnswersCache = null;
    this.update();
  }

  toggleEditMode() {
    if(this.readOnly) {
      alert('Cannot edit lab-associated flashcards in read-only mode');
      return;
    }
    if(this.cardset.cards.length === 0) return;
    const card = this.cardset.cards[this.cardset.index];
    this.editBuffer = new Card(card.id, card.question, [...card.answers].sort((a,b)=>a.id-b.id), card.info);
    this.editBuffer.isDraft = card.isDraft;
    this.isEditing = true;
    this.update();
  }

  syncBufferFromDOM() {
    if(!this.editBuffer) return;
    this.editBuffer.question = document.getElementById('edit-q').value;
    this.editBuffer.info = document.getElementById('edit-info').value;
    const domRows = document.querySelectorAll('.edit-row');
    this.editBuffer.answers = [];
    domRows.forEach((row, i) => {
      const txtArea = row.querySelector('textarea');
      this.editBuffer.answers.push(new Answer(parseInt(txtArea.dataset.id), txtArea.value, document.getElementById(`edit-type-${i}`).checked ? "true" : "false"));
    });
  }

  addAnswerRow() {
    this.syncBufferFromDOM();
    const ids = this.editBuffer.answers.map(a => a.id);
    let nextId = 1; while(ids.includes(nextId)) nextId++;
    this.editBuffer.answers.push(new Answer(nextId, "", "false"));
    this.update();
  }

  removeRow(id) {
    this.syncBufferFromDOM();
    this.editBuffer.answers = this.editBuffer.answers.filter(a => a.id !== id);
    this.update();
  }

  saveCard() {
    this.syncBufferFromDOM();
    this.editBuffer.isDraft = false;
    this.cardset.cards[this.cardset.index] = this.editBuffer;
    this.cardset.meta.modified = getISOString();
    this.saveSession();
    this.isEditing = false;
    this.editBuffer = null;
    this.shuffledAnswersCache = null;
    this.update();
  }

  cancelEdit() {
    const originalCard = this.cardset.cards[this.cardset.index];
    if(originalCard.isDraft) {
      this.cardset.cards.splice(this.cardset.index, 1);
      this.cardset.index = Math.max(0, this.cardset.index - 1);
    }
    this.isEditing = false;
    this.editBuffer = null;
    this.update();
  }

  addCard() {
    if(this.readOnly) {
      alert('Cannot add cards in read-only mode');
      return;
    }
    const newCard = new Card(Date.now(), "", [
      new Answer(1, "", "false"), new Answer(2, "", "false"), new Answer(3, "", "false"), new Answer(4, "", "false")
    ]);
    newCard.isDraft = true;
    this.cardset.cards.push(newCard);
    this.cardset.index = this.cardset.cards.length - 1;
    this.toggleEditMode();
  }

  deleteCard() {
    if(this.readOnly) {
      alert('Cannot delete cards in read-only mode');
      return;
    }
    if(confirm("Delete this card?")) {
      this.cardset.cards.splice(this.cardset.index, 1);
      this.cardset.index = Math.max(0, this.cardset.index - 1);
      this.saveSession();
      this.update();
    }
  }
  
  togglePreview(key) { this.view.togglePreviewClass(key); }
  
  toggleQuiz() {
    if(this.isQuiz) {
      this.showQuizResults(true);
    } else {
      this.isQuiz = true;
      this.cardset.cards = this.cardset.cards.sort(() => Math.random() - 0.5);
      this.cardset.index = 0;
      this.quizScores = [];
      this.timer.seconds = 0;
      this.timer.interval = setInterval(() => {
        this.timer.seconds++;
        const min = Math.floor(this.timer.seconds/60).toString().padStart(2,'0');
        const sec = (this.timer.seconds%60).toString().padStart(2,'0');
        document.getElementById('timer-display').innerText = `${min}:${sec}`;
      }, 1000);
      this.shuffledAnswersCache = null;
      this.update();
    }
  }

  showQuizResults(earlyExit = false) {
    clearInterval(this.timer.interval);
    const answered = this.quizScores.filter(s => s !== undefined).length;
    const correct = this.quizScores.filter(s => s === true).length;
    const totalCards = this.cardset.cards.length;
    const base = answered;
    const chart = this.getChartHTML(correct, base - correct, base);
    const title = earlyExit ? "Partial Results" : "Final Results";
    const subtext = `Answered: ${answered} / ${totalCards}`;
    this.view.renderResults(correct, base, chart, title, subtext);
  }

  restartQuiz() { this.exitQuiz(); setTimeout(() => this.toggleQuiz(), 100); }
  
  exitQuiz() {
    this.isQuiz = false;
    clearInterval(this.timer.interval);
    this.quizScores = [];
    this.timer.seconds = 0;
    document.getElementById('timer-display').innerText = "00:00";
    this.shuffledAnswersCache = null;
    this.update();
  }

  getChartHTML(correct, wrong, total) {
    const cPct = total > 0 ? (correct / total) * 100 : 0;
    const wPct = total > 0 ? (wrong / total) * 100 : 0;
    return `<div class="chart-container"><div class="chart-bar-wrapper"><div class="w3-small" style="width:60px">Correct</div><div class="chart-track"><div class="chart-fill w3-green" style="width:${cPct}%"></div></div><div class="w3-small">${correct}</div></div><div class="chart-bar-wrapper"><div class="w3-small" style="width:60px">Wrong</div><div class="chart-track"><div class="chart-fill w3-red" style="width:${wPct}%"></div></div><div class="w3-small">${wrong}</div></div></div>`;
  }

  newSet() { const n = prompt("Set Name:"); if(n) { this.cardset = new CardSet(n); this.saveSession(); this.update(); } }
  triggerFileImport() { document.getElementById('file-input').click(); }
  handleFileImport(e) {
    const f = e.target.files[0]; if(!f) return;
    const r = new FileReader();
    r.onload = (evt) => {
      try {
        const data = JSON.parse(evt.target.result);
        let sourceMeta = null;
        let sourceCards = [];
        let setName = f.name.replace('.json','');
        if (data.set) {
          sourceMeta = data.set.meta;
          sourceCards = data.set.cards;
        } else if (data.card && data.card.set) {
          sourceMeta = data.card.set.meta;
          sourceCards = data.card.set.cards;
        } else if (data.cards) {
          sourceMeta = data.meta;
          sourceCards = data.cards;
        } else if (Array.isArray(data)) {
          sourceCards = data;
        }
        if (!sourceCards) throw new Error("No cards found");
        this.cardset = new CardSet(setName, f.name);
        this.cardset.cards = sourceCards.map(c => new Card(c.id, c.question, c.answers, c.info));
        if (sourceMeta) {
          if (sourceMeta.name) this.cardset.meta.name = sourceMeta.name;
          if (sourceMeta.created) this.cardset.meta.created = convertTo24h(sourceMeta.created);
          if (sourceMeta.modified) this.cardset.meta.modified = convertTo24h(sourceMeta.modified);
        }
        this.saveSession();
        this.update();
      } catch(err) { alert("Invalid JSON: " + err.message); console.error(err); }
    };
    r.readAsText(f);
  }

  exportSet() {
    const defaultName = this.cardset.meta.name.replace(/ /g, '_');
    const filename = prompt("Export Filename:", defaultName);
    if (filename) {
      const data = { set: this.cardset, version: VERSION };
      const blob = new Blob([JSON.stringify(data, null, 2)], {type:'application/json'});
      const a = document.createElement('a');
      a.download = filename.endsWith('.json') ? filename : filename + ".json";
      a.href = URL.createObjectURL(blob);
      a.click();
    }
  }

  openRawImport() {
    this.view.showModal("Import via Paste",
      `<div class="import-hint-box w3-text-blue"><strong>Format:</strong> Question text, then options on new lines starting with <strong>a)</strong>, <strong>1.</strong>, etc.</div><textarea id="raw-import-area" class="w3-input" style="height:200px;" placeholder="e.g.\nWhat is 2+2?\na) 3\nb) 4" oninput="app.view.autoExpand(this)"></textarea>`,
      `<button class="w3-button w3-blue w3-round" onclick="app.processRawImport()">Import Card</button>`
    );
  }

  processRawImport() {
    const text = document.getElementById('raw-import-area').value;
    if(!text.trim()) return;
    const lines = text.split('\n').map(l => l.trim()).filter(l => l !== "");
    let q = ""; let ansObjects = [];
    let nextId = 1;
    lines.forEach(line => {
      if (/^[a-zA-Z0-9][\.\)]/.test(line)) {
        const txt = line.replace(/^[a-zA-Z0-9][\.\)]\s*/, "");
        ansObjects.push(new Answer(nextId++, txt, "false"));
      } else if (ansObjects.length > 0) { ansObjects[ansObjects.length - 1].txt += " " + line;
      } else { q += (q ? "\n" : "") + line; }
    });
    if (q && ansObjects.length > 0) {
      const newCard = new Card(Date.now(), q, ansObjects);
      newCard.isDraft = true;
      this.cardset.cards.push(newCard);
      this.cardset.index = this.cardset.cards.length - 1;
      this.view.closeModal();
      this.toggleEditMode();
    }
  }

  showSetInfo() {
    const m = this.cardset.meta;
    const h = `
    <table class="info-table">
    <tr><td class="info-key">Name</td><td>${m.name}</td></tr>
    <tr><td class="info-key">File</td><td>${m.filename}</td></tr>
    <tr><td class="info-key">Cards</td><td>${this.cardset.cards.length}</td></tr>
    <tr><td class="info-key">Created</td><td>${m.created}</td></tr>
    <tr><td class="info-key">Modified</td><td>${m.modified}</td></tr>
    <tr><td class="info-key">Loaded</td><td>${m.loadedAt || 'N/A'}</td></tr>
    <tr><td class="info-key">App Version</td><td>${VERSION}</td></tr>
    </table>`;
    this.view.showModal("Set Info", h, `<button class="w3-button w3-blue w3-round" onclick="app.closeModal()">Close</button>`);
  }

  showLiveStats() {
    const correct = this.quizScores.filter(s => s === true).length;
    const answered = this.quizScores.filter(s => s !== undefined).length;
    const chart = this.getChartHTML(correct, answered - correct, answered);
    this.view.showModal("Quiz Progress", `<div style="text-align:center; margin-bottom:10px; font-size:2em; font-weight:bold; color:var(--primary)">${answered > 0 ? Math.round(correct/answered*100) : 0}%</div>${chart}`, `<button class="w3-button w3-blue w3-round" onclick="app.closeModal()">Close</button>`);
  }

  closeModal() {
    this.view.closeModal();
  }

}

let app;
document.addEventListener('DOMContentLoaded', () => {
  if (document.getElementById('card-app') && typeof FlashCardsController !== 'undefined') {
    if (!window.flashcardsApp) {
      window.flashcardsApp = new FlashCardsController(new FlashCardsView());
      app = window.flashcardsApp;
    }
  }
});
