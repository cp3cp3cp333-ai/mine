const PIECES = {
  carrot: { emoji: "🥕", name: "胡萝卜" },
  hay: { emoji: "🌾", name: "干草卷" },
  mushroom: { emoji: "🍄", name: "蘑菇" },
  grass: { emoji: "🌿", name: "青草" },
  grapes: { emoji: "🍇", name: "葡萄" },
  bucket: { emoji: "🪣", name: "水桶" },
  sheep: { emoji: "🐑", name: "小羊" },
};

// 每组普通棋子数量都是行数的整数倍；空位由 level 的棋盘容量减去 pieces 数量得到。
// 列数组从底部到顶部存储，关卡布局因此完全固定，不依赖随机数。
const LEVELS = [
  {
    number: 1,
    columns: 5,
    rows: 6,
    pieces: [
      ["carrot", "hay", "mushroom"],
      ["mushroom", "carrot", "hay", "carrot"],
      ["hay", "mushroom", "carrot"],
      ["carrot", "mushroom", "hay", "mushroom"],
      ["hay", "carrot", "hay", "mushroom"],
    ],
    sheepOnBoard: 0,
  },
  {
    number: 2,
    columns: 6,
    rows: 6,
    pieces: [
      ["grass", "carrot", "bucket", "grapes"],
      ["mushroom", "grass", "carrot", "bucket"],
      ["grapes", "mushroom", "grass", "carrot"],
      ["carrot", "bucket", "grapes", "mushroom"],
      ["bucket", "grapes", "mushroom", "grass"],
      ["mushroom", "grass", "carrot", "grapes"],
    ],
    sheepOnBoard: 0,
  },
  {
    number: 3,
    columns: 7,
    rows: 6,
    pieces: [
      ["carrot", "grass", "grapes", "mushroom"],
      ["bucket", "carrot", "grass", "grapes"],
      ["mushroom", "bucket", "carrot", "grass"],
      ["grapes", "mushroom", "bucket", "carrot"],
      ["grass", "grapes", "mushroom", "bucket"],
      ["carrot", "grass", "grapes", "mushroom"],
      ["mushroom", "bucket", "carrot", "grass", "grapes", "mushroom"],
    ],
    sheepOnBoard: 0,
  },
];

const MAX_COLUMNS = 8;
const MAX_ROWS = 12;
const MAX_TEMP_SLOTS = 8;
const MAX_SHEEP = 4;

const dom = {
  board: document.querySelector("#board"),
  boardTip: document.querySelector("#board-tip"),
  levelNumber: document.querySelector("#level-number"),
  levelProgress: document.querySelector("#level-progress"),
  emptyCount: document.querySelector("#empty-count"),
  sheepCount: document.querySelector("#sheep-count"),
  sheepBaskets: document.querySelector("#sheep-baskets"),
  temporarySlots: document.querySelector("#temporary-slots"),
  levelDots: document.querySelector("#level-dots"),
  modalBackdrop: document.querySelector("#modal-backdrop"),
  modalIcon: document.querySelector("#modal-icon"),
  modalTitle: document.querySelector("#modal-title"),
  modalCopy: document.querySelector("#modal-copy"),
  modalActions: document.querySelector("#modal-actions"),
  undoButton: document.querySelector("#undo-button"),
  shuffleButton: document.querySelector("#shuffle-button"),
  prevLevel: document.querySelector("#prev-level"),
  nextLevel: document.querySelector("#next-level"),
  soundButton: document.querySelector("#sound-button"),
  helpButton: document.querySelector("#help-button"),
};

const state = {
  levelIndex: 0,
  columns: [],
  selection: null,
  temporarySlots: [],
  tempSlotCount: 2,
  sheepBaskets: 0,
  history: [],
  shuffleUsed: false,
  undoUsed: false,
  continueUsed: false,
  gameOver: false,
  soundOn: true,
};

const clone = (value) => JSON.parse(JSON.stringify(value));
const level = () => LEVELS[state.levelIndex];
const pieceInfo = (type) => PIECES[type] || PIECES.carrot;
const allColumnsEmpty = () => state.columns.every((column) => column.items.length === 0 || column.locked);
const boardPieceCount = () => state.columns.reduce((sum, column) => sum + column.items.length, 0);

function snapshot() {
  return {
    columns: clone(state.columns),
    temporarySlots: clone(state.temporarySlots),
    tempSlotCount: state.tempSlotCount,
    sheepBaskets: state.sheepBaskets,
  };
}

function restore(snapshotValue) {
  state.columns = clone(snapshotValue.columns);
  state.temporarySlots = clone(snapshotValue.temporarySlots);
  state.tempSlotCount = snapshotValue.tempSlotCount;
  state.sheepBaskets = snapshotValue.sheepBaskets;
  state.selection = null;
  state.gameOver = false;
  render();
}

function saveHistory() {
  state.history.push(snapshot());
  if (state.history.length > 40) state.history.shift();
}

function showTip(message) {
  dom.boardTip.textContent = message;
  window.clearTimeout(showTip.timer);
  showTip.timer = window.setTimeout(() => {
    dom.boardTip.textContent = "点击一列，再点击目标列";
  }, 2400);
}

function showModal({ icon = "🌿", title, copy, actions }) {
  dom.modalIcon.textContent = icon;
  dom.modalTitle.textContent = title;
  dom.modalCopy.textContent = copy;
  dom.modalActions.replaceChildren();
  actions.forEach(({ label, className = "", onClick }) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = `modal__button ${className}`.trim();
    button.textContent = label;
    button.addEventListener("click", () => {
      if (onClick) onClick();
    }, { once: true });
    dom.modalActions.append(button);
  });
  dom.modalBackdrop.hidden = false;
}

function closeModal() {
  dom.modalBackdrop.hidden = true;
  dom.modalActions.replaceChildren();
}

function showHelp() {
  showModal({
    icon: "🐑",
    title: "怎么玩？",
    copy: "点一列，再点另一列，把顶部相同的棋子放到一起。\n同类棋子凑满一列会锁定。每关固定布局，留有空位可以周转。",
    actions: [{ label: "知道啦", onClick: closeModal }],
  });
}

function startLevel(index = state.levelIndex) {
  const next = LEVELS[index];
  if (!next || next.columns > MAX_COLUMNS || next.rows > MAX_ROWS) return;
  state.levelIndex = index;
  state.columns = next.pieces.map((items) => ({ items: [...items], locked: false }));
  state.temporarySlots = [];
  state.tempSlotCount = 2;
  state.sheepBaskets = 0;
  state.selection = null;
  state.history = [];
  state.shuffleUsed = false;
  state.undoUsed = false;
  state.continueUsed = false;
  state.gameOver = false;
  for (let i = 0; i < (next.sheepOnBoard || 0); i += 1) {
    const column = state.columns[i % state.columns.length];
    column.items.push("sheep");
  }
  collectVisibleSheep();
  render();
  showTip(`第 ${next.number} 关 · 固定布局`);
}

function render() {
  const currentLevel = level();
  dom.levelNumber.textContent = currentLevel.number;
  dom.board.style.setProperty("--columns", currentLevel.columns);
  dom.board.replaceChildren();
  state.columns.forEach((column, columnIndex) => {
    const columnButton = document.createElement("button");
    columnButton.type = "button";
    columnButton.className = "board-column";
    columnButton.setAttribute("role", "gridcell");
    columnButton.setAttribute("aria-label", `第 ${columnIndex + 1} 列`);
    if (column.locked) columnButton.classList.add("is-locked");
    if (state.selection?.kind === "column" && state.selection.index === columnIndex) columnButton.classList.add("is-selected");
    if (state.selection && state.selection.kind === "column" && state.selection.index !== columnIndex && canReceiveFromSelection(columnIndex)) columnButton.classList.add("is-target");
    const selectedSource = state.selection?.kind === "column" && state.selection.index === columnIndex;
    const movingStart = selectedSource ? column.items.length - topRunLength(column) : column.items.length;
    column.items.forEach((type, itemIndex) => {
      const piece = document.createElement("span");
      piece.className = `piece piece--${type}`;
      if (itemIndex === column.items.length - 1) piece.classList.add("is-top");
      if (selectedSource && itemIndex >= movingStart) piece.classList.add("is-moving");
      piece.textContent = pieceInfo(type).emoji;
      piece.title = pieceInfo(type).name;
      columnButton.append(piece);
    });
    if (column.locked) {
      const lock = document.createElement("span");
      lock.className = "board-column__lock";
      lock.textContent = "✓";
      columnButton.append(lock);
    }
    columnButton.addEventListener("click", () => handleColumnClick(columnIndex));
    dom.board.append(columnButton);
  });

  const totalCapacity = currentLevel.columns * currentLevel.rows;
  dom.emptyCount.textContent = Math.max(0, totalCapacity - boardPieceCount());
  dom.levelProgress.textContent = `${state.sheepBaskets}/${MAX_SHEEP}`;
  dom.sheepCount.textContent = `${state.sheepBaskets}/${MAX_SHEEP}`;
  renderSheepBaskets();
  renderTemporarySlots();
  renderLevelDots();
  dom.undoButton.disabled = state.history.length === 0 || state.undoUsed;
  dom.shuffleButton.disabled = state.shuffleUsed || state.gameOver;
}

function renderSheepBaskets() {
  dom.sheepBaskets.replaceChildren();
  for (let i = 0; i < MAX_SHEEP; i += 1) {
    const basket = document.createElement("div");
    basket.className = "sheep-basket";
    if (i >= state.sheepBaskets) basket.classList.add("is-empty");
    if (i < state.sheepBaskets) {
      const sheep = document.createElement("span");
      sheep.className = "sheep-basket__sheep";
      sheep.textContent = "🐑";
      basket.append(sheep);
    }
    basket.setAttribute("aria-label", i < state.sheepBaskets ? "已放入小羊" : "空篮子");
    dom.sheepBaskets.append(basket);
  }
}

function renderTemporarySlots() {
  dom.temporarySlots.replaceChildren();
  for (let index = 0; index < MAX_TEMP_SLOTS; index += 1) {
    const slot = document.createElement("button");
    slot.type = "button";
    slot.className = "temporary-slot";
    if (index >= state.tempSlotCount) slot.classList.add("is-hidden");
    const type = state.temporarySlots[index];
    if (type) {
      slot.classList.add("is-filled");
      slot.textContent = pieceInfo(type).emoji;
      slot.title = `${pieceInfo(type).name}临时位`;
    } else {
      const plus = document.createElement("span");
      plus.className = "temporary-slot__plus";
      plus.textContent = "+";
      slot.append(plus);
      slot.title = "空临时位";
    }
    if (state.selection?.kind === "temp" && state.selection.index === index) slot.classList.add("is-selected");
    slot.addEventListener("click", () => handleTemporaryClick(index));
    dom.temporarySlots.append(slot);
  }
}

function renderLevelDots() {
  dom.levelDots.replaceChildren();
  for (let i = 0; i < 12; i += 1) {
    const dot = document.createElement("span");
    dot.className = "level-dot";
    if (i === state.levelIndex) dot.classList.add("is-current");
    if (i >= LEVELS.length) dot.classList.add("is-locked");
    dom.levelDots.append(dot);
  }
}

function topType(column) {
  return column.items[column.items.length - 1];
}

function topRunLength(column) {
  if (!column.items.length) return 0;
  const type = topType(column);
  let count = 0;
  for (let i = column.items.length - 1; i >= 0 && column.items[i] === type; i -= 1) count += 1;
  return count;
}

function isFullSame(column) {
  return column.items.length === level().rows && column.items.length > 0 && column.items.every((type) => type === column.items[0]);
}

function updateLocks() {
  state.columns.forEach((column) => {
    if (!column.locked && isFullSame(column)) column.locked = true;
  });
}

function collectVisibleSheep() {
  let collected = true;
  while (collected && state.sheepBaskets < MAX_SHEEP) {
    collected = false;
    for (const column of state.columns) {
      if (topType(column) === "sheep" && state.sheepBaskets < MAX_SHEEP) {
        column.items.pop();
        state.sheepBaskets += 1;
        collected = true;
      }
    }
  }
}

function canReceive(type, targetIndex) {
  const target = state.columns[targetIndex];
  if (!target || target.locked || target.items.length >= level().rows) return false;
  return target.items.length === 0 || topType(target) === type;
}

function canReceiveFromSelection(targetIndex) {
  if (!state.selection || state.selection.kind !== "column" || targetIndex === state.selection.index) return false;
  const source = state.columns[state.selection.index];
  return Boolean(source && source.items.length && canReceive(topType(source), targetIndex));
}

function handleColumnClick(columnIndex) {
  const column = state.columns[columnIndex];
  if (!column || state.gameOver) return;
  if (state.selection?.kind === "temp") {
    moveFromTemporary(state.selection.index, columnIndex);
    return;
  }
  if (column.locked) {
    showTip("这一列已经整理好了");
    return;
  }
  if (state.selection?.kind === "column") {
    if (state.selection.index === columnIndex) {
      state.selection = null;
      render();
      showTip("已取消选择");
      return;
    }
    moveColumn(state.selection.index, columnIndex);
    return;
  }
  if (!column.items.length) {
    showTip("空列可以作为周转位");
    return;
  }
  if (topType(column) === "sheep") {
    saveHistory();
    collectVisibleSheep();
    render();
    showTip("小羊回到篮子里啦");
    checkAfterAction();
    return;
  }
  state.selection = { kind: "column", index: columnIndex };
  render();
  showTip(`已选第 ${columnIndex + 1} 列 · 再点目标列`);
}

function moveColumn(sourceIndex, targetIndex) {
  const source = state.columns[sourceIndex];
  const target = state.columns[targetIndex];
  if (!source || !target || source.locked || target.locked) {
    showTip("锁定的列不能移动");
    return;
  }
  const type = topType(source);
  if (!canReceive(type, targetIndex)) {
    showTip("只能放到空列或同样的棋子上");
    return;
  }
  const runLength = topRunLength(source);
  const available = level().rows - target.items.length;
  const moved = Math.min(runLength, available);
  if (moved < 1) return;
  saveHistory();
  source.items.splice(source.items.length - moved, moved);
  target.items.push(...Array(moved).fill(type));
  state.selection = null;
  collectVisibleSheep();
  updateLocks();
  render();
  showTip(moved < runLength ? "列空间不够，多出的棋子留在原位" : `${pieceInfo(type).name}移动成功`);
  checkAfterAction();
}

function handleTemporaryClick(slotIndex) {
  if (state.gameOver || slotIndex >= state.tempSlotCount) return;
  const current = state.temporarySlots[slotIndex];
  if (state.selection?.kind === "column") {
    if (current) {
      showTip("这个临时位已经有棋子了");
      return;
    }
    const source = state.columns[state.selection.index];
    if (!source?.items.length || source.locked) return;
    saveHistory();
    state.temporarySlots[slotIndex] = source.items.pop();
    state.selection = null;
    collectVisibleSheep();
    updateLocks();
    render();
    showTip("已放入临时位");
    checkAfterAction();
    return;
  }
  if (state.selection?.kind === "temp") {
    if (state.selection.index === slotIndex) {
      state.selection = null;
      render();
    } else if (!current) {
      state.temporarySlots[slotIndex] = state.temporarySlots[state.selection.index];
      state.temporarySlots[state.selection.index] = null;
      state.selection = null;
      render();
    }
    return;
  }
  if (current) {
    state.selection = { kind: "temp", index: slotIndex };
    render();
    showTip("已选临时棋子 · 再点目标列");
  }
}

function moveFromTemporary(slotIndex, targetIndex) {
  const type = state.temporarySlots[slotIndex];
  if (!type) return;
  if (!canReceive(type, targetIndex)) {
    showTip("只能放到空列或同样的棋子上");
    return;
  }
  saveHistory();
  state.columns[targetIndex].items.push(type);
  state.temporarySlots[slotIndex] = null;
  state.selection = null;
  updateLocks();
  render();
  showTip(`${pieceInfo(type).name}回到棋盘`);
  checkAfterAction();
}

function hasLegalMove() {
  const emptyTemp = state.temporarySlots.slice(0, state.tempSlotCount).filter((item) => !item).length;
  for (const [index, column] of state.columns.entries()) {
    if (column.locked || !column.items.length) continue;
    const type = topType(column);
    if (type === "sheep" && state.sheepBaskets < MAX_SHEEP) return true;
    if (emptyTemp > 0) return true;
    if (state.columns.some((target, targetIndex) => targetIndex !== index && canReceive(type, targetIndex))) return true;
  }
  for (const type of state.temporarySlots.slice(0, state.tempSlotCount)) {
    if (type && state.columns.some((target, targetIndex) => canReceive(type, targetIndex))) return true;
  }
  return false;
}

function checkAfterAction() {
  if (allColumnsEmpty() && state.temporarySlots.slice(0, state.tempSlotCount).every((item) => !item)) {
    state.gameOver = true;
    render();
    showModal({
      icon: "🎉",
      title: "闯关成功！",
      copy: `第 ${level().number} 关完成\n下一关会有更多棋子和更多周转空间。`,
      actions: [
        { label: "下一关", onClick: () => { closeModal(); nextLevel(); } },
        { label: "再玩一次", className: "modal__button--secondary", onClick: () => { closeModal(); startLevel(); } },
      ],
    });
    return;
  }
  if (!hasLegalMove()) {
    state.gameOver = true;
    render();
    const canContinue = !state.continueUsed && state.tempSlotCount < MAX_TEMP_SLOTS;
    showModal({
      icon: "😵",
      title: "棋子卡住啦",
      copy: canContinue ? "顶部没有可以移动的位置。看一次广告，增加一个临时空位继续？" : "顶部没有可以移动的位置，重新挑战这一关吧。",
      actions: [
        ...(canContinue ? [{ label: "看广告继续", onClick: continueAfterAd }] : []),
        { label: "重新开始", className: "modal__button--secondary", onClick: () => { closeModal(); startLevel(); } },
      ],
    });
  }
}

function continueAfterAd() {
  state.continueUsed = true;
  state.tempSlotCount = Math.min(MAX_TEMP_SLOTS, state.tempSlotCount + 1);
  state.gameOver = false;
  closeModal();
  render();
  showTip("临时空位 +1，继续加油！");
}

function shuffleColumns() {
  if (state.shuffleUsed || state.gameOver) return;
  state.shuffleUsed = true;
  saveHistory();
  state.columns.forEach((column) => {
    if (column.locked || column.items.length < 2) return;
    const order = [];
    column.items.forEach((type) => { if (!order.includes(type)) order.push(type); });
    column.items = order.flatMap((type) => column.items.filter((item) => item === type));
  });
  updateLocks();
  render();
  showTip("同类棋子已经整理到一起");
  checkAfterAction();
}

function undoMove() {
  if (state.undoUsed || !state.history.length || state.gameOver) return;
  const previous = state.history.pop();
  state.undoUsed = true;
  restore(previous);
  showTip("已经撤回一步");
}

function nextLevel() {
  if (state.levelIndex + 1 >= LEVELS.length) {
    showModal({ icon: "🌟", title: "新关卡正在准备", copy: "前 3 关原型已经开放，后续关卡会继续扩展到 8×12 棋盘。", actions: [{ label: "回到第 1 关", onClick: () => { closeModal(); startLevel(0); } }] });
    return;
  }
  startLevel(state.levelIndex + 1);
}

function previousLevel() {
  if (state.levelIndex === 0) return;
  startLevel(state.levelIndex - 1);
}

dom.shuffleButton.addEventListener("click", () => showModal({
  icon: "↝",
  title: "整理棋子",
  copy: "看一次广告，把每列相同的棋子整理到一起。列号不会改变。",
  actions: [
    { label: "看广告使用", onClick: () => { closeModal(); shuffleColumns(); } },
    { label: "先不用", className: "modal__button--secondary", onClick: closeModal },
  ],
}));
dom.undoButton.addEventListener("click", () => showModal({
  icon: "↶",
  title: "撤回一步",
  copy: "看一次广告，回到上一步的棋盘状态。",
  actions: [
    { label: "看广告使用", onClick: () => { closeModal(); undoMove(); } },
    { label: "先不用", className: "modal__button--secondary", onClick: closeModal },
  ],
}));
document.querySelector('[data-ad-action="temp"]').addEventListener("click", () => {
  if (state.tempSlotCount >= MAX_TEMP_SLOTS) {
    showTip("临时空位已经达到 8 格");
    return;
  }
  showModal({
    icon: "＋",
    title: "增加临时空位",
    copy: "看一次广告，增加一个临时空位。最多可以增加到 8 格。",
    actions: [
      { label: "看广告增加", onClick: continueAfterAd },
      { label: "先不用", className: "modal__button--secondary", onClick: closeModal },
    ],
  });
});
dom.helpButton.addEventListener("click", showHelp);
dom.soundButton.addEventListener("click", () => {
  state.soundOn = !state.soundOn;
  dom.soundButton.textContent = state.soundOn ? "♫" : "×";
  showTip(state.soundOn ? "音效已开启" : "音效已关闭");
});
dom.prevLevel.addEventListener("click", previousLevel);
dom.nextLevel.addEventListener("click", nextLevel);
dom.modalBackdrop.addEventListener("click", (event) => {
  if (event.target === dom.modalBackdrop) closeModal();
});

startLevel(0);

