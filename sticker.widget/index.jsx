import { React, run } from 'uebersicht';

export const refreshFrequency = false;
export const command = '';

const BLANK_SQUARE_SIZE = 100;
const BASE_SIZE = 180;
const SHADOW_PAD = 24;

const STORAGE_INSTANCES_KEY = 'sticker_widget_instances';
const STORAGE_OPACITY_KEY = 'sticker_widget_opacity';
const STORAGE_SHADOW_KEY = 'sticker_widget_shadow';
const STORAGE_SNAP_KEY = 'sticker_widget_snapping';
const STORAGE_AUDIO_SYNC_KEY = 'sticker_widget_audio_sync';

const WIDGET_ORDER_KEY = 'uebersicht_widget_order';
const DEFAULT_WIDGET_ORDER = ['sticker', 'cava', 'shell', 'nowplaying'];

const getWidgetZIndex = (widgetId) => {
  try {
    const raw = localStorage.getItem(WIDGET_ORDER_KEY);
    let order = raw ? JSON.parse(raw) : [...DEFAULT_WIDGET_ORDER];
    if (!Array.isArray(order)) order = [...DEFAULT_WIDGET_ORDER];
    let idx = order.indexOf(widgetId);
    if (idx === -1) {
      order.push(widgetId);
      localStorage.setItem(WIDGET_ORDER_KEY, JSON.stringify(order));
      idx = order.length - 1;
    }
    return 100 + idx * 50;
  } catch (e) {
    return 100;
  }
};

const reorderWidget = (widgetId, action) => {
  try {
    const raw = localStorage.getItem(WIDGET_ORDER_KEY);
    let order = raw ? JSON.parse(raw) : [...DEFAULT_WIDGET_ORDER];
    if (!Array.isArray(order)) order = [...DEFAULT_WIDGET_ORDER];
    if (!order.includes(widgetId)) {
      order.push(widgetId);
    }
    const idx = order.indexOf(widgetId);
    if (action === 'ORDER_FRONT' || action === 'BRING_TO_FRONT') {
      order.splice(idx, 1);
      order.push(widgetId);
    } else if (action === 'ORDER_BACK' || action === 'SEND_TO_BACK') {
      order.splice(idx, 1);
      order.unshift(widgetId);
    } else if (action === 'ORDER_FORWARD' || action === 'BRING_FORWARD') {
      if (idx < order.length - 1) {
        const temp = order[idx];
        order[idx] = order[idx + 1];
        order[idx + 1] = temp;
      }
    } else if (action === 'ORDER_BACKWARD' || action === 'SEND_BACKWARD') {
      if (idx > 0) {
        const temp = order[idx];
        order[idx] = order[idx - 1];
        order[idx - 1] = temp;
      }
    }
    localStorage.setItem(WIDGET_ORDER_KEY, JSON.stringify(order));
    if (typeof window !== 'undefined') {
      window.dispatchEvent(new CustomEvent('uebersicht:order-changed', { detail: { order } }));
    }
  } catch (e) {}
};

const SNAP_THRESHOLD = 6;
const SNAP_EDGE_TOLERANCE = 3;
const SNAP_MARGIN_X = 15;
const SNAP_MARGIN_TOP = 14;
const SNAP_MARGIN_BOTTOM = 14;

let lastClickTimestamp = 0;
let audioTimer = null;
let isCheckingAudio = false;
let currentDispatch = null;
let currentWidgetState = null;

// Sprite Sheet Animation Engine
const stickerMetaCache = {};
const sheetImageCache = {};
const animFrameState = {};
let globalRafId = null;

const loadStickerMeta = (stickerPath, callback) => {
  if (!stickerPath) return;
  if (stickerMetaCache[stickerPath]) {
    if (callback) callback(stickerMetaCache[stickerPath]);
    return;
  }
  const filename = stickerPath.split('/').pop();
  const scriptPath = '$HOME/Library/Application Support/Übersicht/widgets/sticker.widget/sheet_generator.py';
  const stickersDir = '$HOME/Library/Application Support/Übersicht/widgets/sticker.widget/stickers';
  const fallbackScript = './sticker.widget/sheet_generator.py';
  const fallbackStickers = './sticker.widget/stickers';

  const cmd = `"/usr/bin/python3" "${scriptPath}" "${stickersDir}/${filename}" "${stickersDir}" 2>/dev/null || "/usr/bin/python3" "${fallbackScript}" "${fallbackStickers}/${filename}" "${fallbackStickers}" 2>/dev/null`;

  run(cmd, (err, output) => {
    if (err || !output) return;
    try {
      const meta = JSON.parse(output.trim());
      if (meta && meta.sheet) {
        stickerMetaCache[stickerPath] = meta;
        if (!sheetImageCache[meta.sheet]) {
          const img = new Image();
          img.src = meta.sheet;
          sheetImageCache[meta.sheet] = img;
        }
        if (callback) callback(meta);
      }
    } catch (e) {}
  });
};

const drawCanvasFrame = (instanceId, stickerPath, frameIndex) => {
  const canvas = document.getElementById(`sticker-canvas-${instanceId}`);
  if (!canvas) return;
  const meta = stickerMetaCache[stickerPath];
  if (!meta) return;

  const sheet = sheetImageCache[meta.sheet];
  if (!sheet || !sheet.complete || sheet.naturalWidth === 0) {
    if (sheet && !sheet.onload) {
      sheet.onload = () => drawCanvasFrame(instanceId, stickerPath, frameIndex);
    }
    return;
  }

  const ctx = canvas.getContext('2d');
  if (!ctx) return;

  const inst = currentWidgetState?.instances?.find((i) => i.id === instanceId);
  const instScale = inst?.scale ?? 1.0;
  let naturalW = inst?.w;
  let naturalH = inst?.h;
  if (!naturalW || !naturalH) {
    const aspect = meta.width / meta.height;
    if (aspect >= 1) {
      naturalW = BASE_SIZE;
      naturalH = Math.round(BASE_SIZE / aspect);
    } else {
      naturalH = BASE_SIZE;
      naturalW = Math.round(BASE_SIZE * aspect);
    }
  }
  const cardW = Math.round(naturalW * instScale);
  const cardH = Math.round(naturalH * instScale);

  const dpr = (typeof window !== 'undefined' && window.devicePixelRatio) ? window.devicePixelRatio : 1;
  const targetW = Math.round((cardW + SHADOW_PAD * 2) * dpr);
  const targetH = Math.round((cardH + SHADOW_PAD * 2) * dpr);

  if (targetW <= 0 || targetH <= 0) return;

  if (canvas.width !== targetW) canvas.width = targetW;
  if (canvas.height !== targetH) canvas.height = targetH;

  const isAnimated = Boolean(meta.isAnimated && meta.totalFrames > 1);
  const validIndex = isAnimated ? Math.max(0, Math.min(meta.totalFrames - 1, frameIndex || 0)) : 0;
  const cols = meta.cols || 1;
  const col = isAnimated ? (validIndex % cols) : 0;
  const row = isAnimated ? Math.floor(validIndex / cols) : 0;

  const destX = Math.round(SHADOW_PAD * dpr);
  const destY = Math.round(SHADOW_PAD * dpr);
  const destW = Math.round(cardW * dpr);
  const destH = Math.round(cardH * dpr);

  const isDragging = Boolean(currentWidgetState?.isDragging && currentWidgetState?.draggingInstanceId === instanceId);
  const showShadow = currentWidgetState?.shadow !== false && !isDragging;

  ctx.clearRect(0, 0, targetW, targetH);

  if (showShadow) {
    ctx.save();
    ctx.shadowColor = 'rgba(0, 0, 0, 0.35)';
    ctx.shadowBlur = Math.round(12 * dpr);
    ctx.shadowOffsetX = 0;
    ctx.shadowOffsetY = Math.round(4 * dpr);
    ctx.drawImage(sheet, col * meta.width, row * meta.height, meta.width, meta.height, destX, destY, destW, destH);
    ctx.restore();
  } else {
    ctx.drawImage(sheet, col * meta.width, row * meta.height, meta.width, meta.height, destX, destY, destW, destH);
  }
};

const globalAnimLoop = (now) => {
  if (!currentWidgetState) {
    globalRafId = null;
    return;
  }

  const instances = currentWidgetState.instances || [];

  instances.forEach((inst) => {
    if (!inst.sticker) return;
    const meta = stickerMetaCache[inst.sticker];
    if (!meta) {
      loadStickerMeta(inst.sticker, () => {
        const state = animFrameState[inst.id] || { currentFrame: 0, lastFrameTimestamp: performance.now() };
        drawCanvasFrame(inst.id, inst.sticker, state.currentFrame);
      });
      return;
    }

    if (!meta.isAnimated || meta.totalFrames <= 1) {
      drawCanvasFrame(inst.id, inst.sticker, 0);
      return;
    }

    if (!animFrameState[inst.id]) {
      animFrameState[inst.id] = {
        currentFrame: inst.currentFrame || 0,
        lastFrameTimestamp: now,
      };
      drawCanvasFrame(inst.id, inst.sticker, animFrameState[inst.id].currentFrame);
    }

    const state = animFrameState[inst.id];

    if (inst.isPaused) {
      state.lastFrameTimestamp = now;
      return;
    }

    const frameDur = meta.frameDuration || 70;
    const delta = now - state.lastFrameTimestamp;

    if (delta >= frameDur) {
      const steps = Math.floor(delta / frameDur);
      state.currentFrame = (state.currentFrame + steps) % meta.totalFrames;
      state.lastFrameTimestamp = now - (delta % frameDur);
      drawCanvasFrame(inst.id, inst.sticker, state.currentFrame);
    }
  });

  globalRafId = requestAnimationFrame(globalAnimLoop);
};

const ensureAnimLoopRunning = () => {
  if (globalRafId === null && typeof requestAnimationFrame !== 'undefined') {
    globalRafId = requestAnimationFrame(globalAnimLoop);
  }
};

const checkAudio = () => {
  if (isCheckingAudio) return;
  if (!currentWidgetState || !currentWidgetState.audioSync || !currentDispatch) return;

  isCheckingAudio = true;
  const audioCheckPath = '$HOME/Library/Application Support/Übersicht/widgets/sticker.widget/audio_check';
  const fallbackPath = './sticker.widget/audio_check';
  const cmd = `"${audioCheckPath}" 2>/dev/null || "${fallbackPath}" 2>/dev/null`;

  run(cmd, (err, output) => {
    isCheckingAudio = false;
    if (err || !output) return;
    const isPlaying = output.trim() === '1';
    const state = currentWidgetState;
    if (!state || !state.audioSync) return;

    const instances = state.instances || [];
    if (isPlaying) {
      const anyPaused = instances.some((inst) => inst.sticker && inst.isPaused);
      if (anyPaused) {
        currentDispatch({ type: 'AUDIO_STATUS_CHANGED', isPlaying: true });
      }
    } else {
      const anyPlaying = instances.some((inst) => inst.sticker && !inst.isPaused);
      if (anyPlaying) {
        currentDispatch({ type: 'AUDIO_STATUS_CHANGED', isPlaying: false });
      }
    }
  });
};

const getScreenId = () => {
  if (typeof window !== 'undefined' && window.location && window.location.pathname) {
    const parts = window.location.pathname.split('/').filter(Boolean);
    if (parts.length > 0 && !isNaN(Number(parts[0]))) {
      return `screen_${parts[0]}`;
    }
  }
  const w = typeof window !== 'undefined' ? window.screen.width : 1920;
  const h = typeof window !== 'undefined' ? window.screen.height : 1080;
  return `screen_${w}x${h}`;
};

const calculateSnappedPosition = (rawX, rawY, cardWidth, cardHeight, bypassSnap = false, enableSnapping = true) => {
  const winW = typeof window !== 'undefined' ? (window.innerWidth || 1920) : 1920;
  const winH = typeof window !== 'undefined' ? (window.innerHeight || 1080) : 1080;

  const maxX = Math.max(0, winW - cardWidth);
  const maxY = Math.max(0, winH - cardHeight);

  let newX = Math.max(0, Math.min(maxX, rawX));
  let newY = Math.max(0, Math.min(maxY, rawY));

  if (enableSnapping && !bypassSnap) {
    const snapTop = SNAP_MARGIN_TOP;
    const snapBottom = Math.max(0, winH - cardHeight - SNAP_MARGIN_BOTTOM);
    const snapLeft = SNAP_MARGIN_X;
    const snapRight = Math.max(0, winW - cardWidth - SNAP_MARGIN_X);

    if (newX >= snapLeft - SNAP_EDGE_TOLERANCE && newX <= snapLeft + SNAP_THRESHOLD) {
      newX = snapLeft;
    } else if (newX >= snapRight - SNAP_THRESHOLD && newX <= snapRight + SNAP_EDGE_TOLERANCE) {
      newX = snapRight;
    }

    if (newY >= snapTop - SNAP_EDGE_TOLERANCE && newY <= snapTop + SNAP_THRESHOLD) {
      newY = snapTop;
    } else if (newY >= snapBottom - SNAP_THRESHOLD && newY <= snapBottom + SNAP_EDGE_TOLERANCE) {
      newY = snapBottom;
    }
  }

  return { x: newX, y: newY };
};

const getInitialPosition = (cardW, cardH) => {
  const winW = typeof window !== 'undefined' ? (window.innerWidth || 1920) : 1920;
  const winH = typeof window !== 'undefined' ? (window.innerHeight || 1080) : 1080;

  return {
    x: Math.max(SNAP_MARGIN_X, winW - cardW - SNAP_MARGIN_X - 100),
    y: Math.max(SNAP_MARGIN_TOP, winH - cardH - SNAP_MARGIN_BOTTOM - 60),
  };
};

const getInitialInstances = () => {
  const screenId = getScreenId();
  try {
    const saved = typeof localStorage !== 'undefined' ? localStorage.getItem(`${STORAGE_INSTANCES_KEY}_${screenId}`) : null;
    if (saved) {
      const parsed = JSON.parse(saved);
      if (Array.isArray(parsed) && parsed.length > 0) return parsed;
    }
  } catch (e) {}

  const defaultPos = getInitialPosition(BLANK_SQUARE_SIZE, BLANK_SQUARE_SIZE);
  return [{
    id: 'default',
    sticker: null,
    x: defaultPos.x,
    y: defaultPos.y,
    scale: 1.0,
    flipped: false,
    isPaused: false,
    currentFrame: 0,
    w: BASE_SIZE,
    h: BASE_SIZE,
  }];
};

const saveInstances = (instances) => {
  const screenId = getScreenId();
  try {
    localStorage.setItem(`${STORAGE_INSTANCES_KEY}_${screenId}`, JSON.stringify(instances));
    localStorage.setItem(STORAGE_INSTANCES_KEY, JSON.stringify(instances));
  } catch (e) {}
};

const getInitialOpacity = () => {
  try {
    const saved = typeof localStorage !== 'undefined' ? localStorage.getItem(STORAGE_OPACITY_KEY) : null;
    if (saved) {
      const val = parseFloat(saved);
      if (!isNaN(val) && val >= 0.1 && val <= 1.0) return val;
    }
  } catch (e) {}
  return 1.0;
};

const getInitialShadow = () => {
  try {
    const saved = typeof localStorage !== 'undefined' ? localStorage.getItem(STORAGE_SHADOW_KEY) : null;
    if (saved !== null) return saved === 'true';
  } catch (e) {}
  return true;
};

const getInitialSnapping = () => {
  const screenId = getScreenId();
  try {
    const perScreen = typeof localStorage !== 'undefined' ? localStorage.getItem(`${STORAGE_SNAP_KEY}_${screenId}`) : null;
    if (perScreen !== null) return perScreen === 'true';
    const saved = typeof localStorage !== 'undefined' ? localStorage.getItem(STORAGE_SNAP_KEY) : null;
    if (saved !== null) return saved === 'true';
  } catch (e) {}
  return true;
};

const getInitialAudioSync = () => {
  try {
    const saved = typeof localStorage !== 'undefined' ? localStorage.getItem(STORAGE_AUDIO_SYNC_KEY) : null;
    if (saved !== null) return saved === 'true';
  } catch (e) {}
  return false;
};

const initialInstances = getInitialInstances();

export const initialState = {
  instances: initialInstances,
  opacity: getInitialOpacity(),
  shadow: getInitialShadow(),
  enableSnapping: getInitialSnapping(),
  audioSync: getInitialAudioSync(),
  isDragging: false,
  draggingInstanceId: null,
  dragStartX: 0,
  dragStartY: 0,
  startPosX: 0,
  startPosY: 0,
  startW: BLANK_SQUARE_SIZE,
  startH: BLANK_SQUARE_SIZE,
};

export const updateState = (event, previousState) => {
  if (!previousState) return initialState;

  if (event.type === 'START_DRAG') {
    return {
      ...previousState,
      isDragging: true,
      draggingInstanceId: event.instanceId,
      dragStartX: event.clientX,
      dragStartY: event.clientY,
      startPosX: event.startPosX !== undefined ? event.startPosX : (previousState.instances?.[0]?.x || 100),
      startPosY: event.startPosY !== undefined ? event.startPosY : (previousState.instances?.[0]?.y || 100),
      startW: event.w || BLANK_SQUARE_SIZE,
      startH: event.h || BLANK_SQUARE_SIZE,
    };
  }

  if (event.type === 'MOVE_DRAG' && previousState.isDragging && previousState.draggingInstanceId) {
    const deltaX = event.clientX - previousState.dragStartX;
    const deltaY = event.clientY - previousState.dragStartY;
    const cardW = previousState.startW || BLANK_SQUARE_SIZE;
    const cardH = previousState.startH || BLANK_SQUARE_SIZE;
    const bypassSnap = !previousState.enableSnapping || event.bypassSnap;

    const { x: newX, y: newY } = calculateSnappedPosition(
      previousState.startPosX + deltaX,
      previousState.startPosY + deltaY,
      cardW,
      cardH,
      bypassSnap,
      previousState.enableSnapping
    );

    const updatedInstances = (previousState.instances || []).map((inst) => {
      if (inst.id === previousState.draggingInstanceId) {
        return { ...inst, x: newX, y: newY };
      }
      return inst;
    });

    saveInstances(updatedInstances);

    return {
      ...previousState,
      instances: updatedInstances,
    };
  }

  if (event.type === 'END_DRAG') {
    return {
      ...previousState,
      isDragging: false,
      draggingInstanceId: null,
    };
  }

  if (event.type === 'SET_STICKER') {
    const targetId = event.instanceId;
    if (animFrameState[targetId]) {
      animFrameState[targetId].currentFrame = 0;
      animFrameState[targetId].lastFrameTimestamp = performance.now();
    }
    const updatedInstances = (previousState.instances || []).map((inst) => {
      if (inst.id === targetId || (!targetId && inst.id === (previousState.instances?.[0]?.id || 'default'))) {
        return {
          ...inst,
          sticker: event.sticker,
          isPaused: false,
          currentFrame: 0,
          w: null,
          h: null,
        };
      }
      return inst;
    });
    saveInstances(updatedInstances);
    return {
      ...previousState,
      instances: updatedInstances,
    };
  }

  if (event.type === 'CLEAR_FROM_WIDGET') {
    const targetId = event.instanceId;
    delete animFrameState[targetId];
    const updatedInstances = (previousState.instances || []).map((inst) => {
      if (inst.id === targetId || (!targetId && inst.id === (previousState.instances?.[0]?.id || 'default'))) {
        return {
          ...inst,
          sticker: null,
          isPaused: false,
          currentFrame: 0,
          w: null,
          h: null,
        };
      }
      return inst;
    });
    saveInstances(updatedInstances);
    return {
      ...previousState,
      instances: updatedInstances,
    };
  }

  if (event.type === 'CLEAR_STICKER') {
    const targetId = event.instanceId;
    const stickerPath = event.sticker;
    const filename = stickerPath ? stickerPath.split('/').pop() : null;
    delete animFrameState[targetId];
    if (stickerPath) {
      delete stickerMetaCache[stickerPath];
    }
    const updatedInstances = (previousState.instances || []).map((inst) => {
      const isTarget = inst.id === targetId || (!targetId && inst.id === (previousState.instances?.[0]?.id || 'default'));
      const isUsingDeleted = stickerPath && (inst.sticker === stickerPath || (filename && inst.sticker && inst.sticker.endsWith(filename)));
      if (isTarget || isUsingDeleted) {
        delete animFrameState[inst.id];
        return {
          ...inst,
          sticker: null,
          isPaused: false,
          currentFrame: 0,
          w: null,
          h: null,
        };
      }
      return inst;
    });
    saveInstances(updatedInstances);
    return {
      ...previousState,
      instances: updatedInstances,
    };
  }

  if (event.type === 'TOGGLE_PAUSE') {
    const targetId = event.instanceId;
    const updatedInstances = (previousState.instances || []).map((inst) => {
      if (inst.id === targetId || (!targetId && inst.id === (previousState.instances?.[0]?.id || 'default'))) {
        const nextPaused = !inst.isPaused;
        if (!nextPaused && animFrameState[inst.id]) {
          animFrameState[inst.id].lastFrameTimestamp = performance.now();
        }
        return {
          ...inst,
          isPaused: nextPaused,
          currentFrame: animFrameState[inst.id]?.currentFrame ?? inst.currentFrame ?? 0,
        };
      }
      return inst;
    });
    saveInstances(updatedInstances);
    return {
      ...previousState,
      instances: updatedInstances,
    };
  }

  if (event.type === 'TOGGLE_AUDIO_SYNC') {
    const nextSync = !previousState.audioSync;
    try {
      localStorage.setItem(STORAGE_AUDIO_SYNC_KEY, String(nextSync));
    } catch (e) {}

    let updatedInstances = previousState.instances;
    if (!nextSync && updatedInstances) {
      updatedInstances = updatedInstances.map((inst) => {
        if (inst.isPaused) {
          if (animFrameState[inst.id]) animFrameState[inst.id].lastFrameTimestamp = performance.now();
          return { ...inst, isPaused: false };
        }
        return inst;
      });
      saveInstances(updatedInstances);
    }

    return {
      ...previousState,
      audioSync: nextSync,
      instances: updatedInstances || previousState.instances,
    };
  }

  if (event.type === 'AUDIO_STATUS_CHANGED') {
    const isPlaying = event.isPlaying;
    const updatedInstances = (previousState.instances || []).map((inst) => {
      if (inst.sticker) {
        if (isPlaying && inst.isPaused && animFrameState[inst.id]) {
          animFrameState[inst.id].lastFrameTimestamp = performance.now();
        }
        return {
          ...inst,
          isPaused: !isPlaying,
          currentFrame: animFrameState[inst.id]?.currentFrame ?? inst.currentFrame ?? 0,
        };
      }
      return inst;
    });
    saveInstances(updatedInstances);
    return {
      ...previousState,
      instances: updatedInstances,
    };
  }

  if (event.type === 'SET_NATURAL_SIZE') {
    const updatedInstances = (previousState.instances || []).map((inst) => {
      if (inst.id === event.instanceId) {
        return { ...inst, w: event.w, h: event.h };
      }
      return inst;
    });
    saveInstances(updatedInstances);
    return {
      ...previousState,
      instances: updatedInstances,
    };
  }

  if (event.type === 'SET_SCALE') {
    const nextScale = event.scale;
    const targetId = event.instanceId;
    const updatedInstances = (previousState.instances || []).map((inst) => {
      if (!targetId || inst.id === targetId) {
        return { ...inst, scale: nextScale };
      }
      return inst;
    });
    saveInstances(updatedInstances);

    return {
      ...previousState,
      instances: updatedInstances,
    };
  }

  if (event.type === 'TOGGLE_FLIP') {
    const targetId = event.instanceId;
    const updatedInstances = (previousState.instances || []).map((inst) => {
      if (!targetId || inst.id === targetId) {
        return { ...inst, flipped: !inst.flipped };
      }
      return inst;
    });
    saveInstances(updatedInstances);
    return {
      ...previousState,
      instances: updatedInstances,
    };
  }

  if (event.type === 'SET_FLIP') {
    const targetId = event.instanceId;
    const updatedInstances = (previousState.instances || []).map((inst) => {
      if (!targetId || inst.id === targetId) {
        return { ...inst, flipped: event.flipped };
      }
      return inst;
    });
    saveInstances(updatedInstances);
    return {
      ...previousState,
      instances: updatedInstances,
    };
  }

  if (event.type === 'SET_OPACITY') {
    try {
      localStorage.setItem(STORAGE_OPACITY_KEY, String(event.opacity));
    } catch (e) {}
    return {
      ...previousState,
      opacity: event.opacity,
    };
  }

  if (event.type === 'TOGGLE_SHADOW') {
    const nextShadow = !previousState.shadow;
    try {
      localStorage.setItem(STORAGE_SHADOW_KEY, String(nextShadow));
    } catch (e) {}
    return {
      ...previousState,
      shadow: nextShadow,
    };
  }

  if (event.type === 'TOGGLE_SNAPPING') {
    const nextSnap = !previousState.enableSnapping;
    const screenId = getScreenId();
    try {
      localStorage.setItem(`${STORAGE_SNAP_KEY}_${screenId}`, String(nextSnap));
      localStorage.setItem(STORAGE_SNAP_KEY, String(nextSnap));
    } catch (e) {}
    return {
      ...previousState,
      enableSnapping: nextSnap,
    };
  }

  if (event.type === 'RESET_POSITION') {
    const winW = typeof window !== 'undefined' ? (window.innerWidth || 1920) : 1920;
    const winH = typeof window !== 'undefined' ? (window.innerHeight || 1080) : 1080;
    const targetId = event.instanceId;
    const target = (previousState.instances || []).find((i) => i.id === targetId);
    const cardW = target?.sticker ? Math.round((target.w || BASE_SIZE) * (target.scale || 1.0)) : BLANK_SQUARE_SIZE;
    const cardH = target?.sticker ? Math.round((target.h || BASE_SIZE) * (target.scale || 1.0)) : BLANK_SQUARE_SIZE;

    const defaultX = Math.max(SNAP_MARGIN_X, winW - cardW - SNAP_MARGIN_X - 100);
    const defaultY = Math.max(SNAP_MARGIN_TOP, winH - cardH - SNAP_MARGIN_BOTTOM - 60);

    const updatedInstances = (previousState.instances || []).map((inst) => {
      if (inst.id === targetId || (!targetId && inst.id === (previousState.instances?.[0]?.id || 'default'))) {
        return { ...inst, x: defaultX, y: defaultY };
      }
      return inst;
    });

    saveInstances(updatedInstances);

    return {
      ...previousState,
      instances: updatedInstances,
    };
  }

  if (event.type === 'DUPLICATE_WIDGET') {
    const current = previousState.instances && previousState.instances.length > 0
      ? previousState.instances
      : [{ id: 'default', x: 100, y: 100, scale: 1.0, flipped: false, sticker: null }];
    const target = current.find((i) => i.id === event.instanceId) || current[current.length - 1];
    const newInst = {
      ...target,
      id: `inst_${Date.now()}_${Math.random().toString(36).substr(2, 4)}`,
      x: (target.x ?? 100) + 30,
      y: (target.y ?? 100) + 30,
      sticker: target.sticker || null,
    };
    const updatedInstances = [...current, newInst];
    saveInstances(updatedInstances);
    return {
      ...previousState,
      instances: updatedInstances,
    };
  }

  if (event.type === 'REMOVE_WIDGET') {
    const current = previousState.instances || [];
    if (current.length > 1) {
      const updatedInstances = current.filter((i) => i.id !== event.instanceId);
      saveInstances(updatedInstances);
      return {
        ...previousState,
        instances: updatedInstances,
      };
    } else {
      const wid = event.widgetId || 'sticker-widget-index-jsx';
      run(`osascript -e 'tell application id "tracesOf.Uebersicht" to set hidden of widget id "${wid}" to true'`);
      return previousState;
    }
  }

  if (event.type === 'ORDER_CHANGED') {
    return {
      ...previousState,
      orderTick: Date.now(),
    };
  }

  return previousState;
};

if (typeof window !== 'undefined' && !window.__uebersicht_order_listener_sticker) {
  window.__uebersicht_order_listener_sticker = true;
  window.addEventListener('uebersicht:order-changed', () => {
    if (currentDispatch) {
      currentDispatch({ type: 'ORDER_CHANGED' });
    }
  });
}

export const render = (state, dispatch) => {
  const currentState = state || initialState;
  const {
    opacity = 1.0,
    shadow = true,
    enableSnapping = true,
    audioSync = false,
  } = currentState;

  currentDispatch = dispatch;
  currentWidgetState = currentState;

  // Ensure sprite sheet animation loop is running
  ensureAnimLoopRunning();

  // Manage Audio Sync Polling (fast 200ms responsive loop)
  if (audioSync && !audioTimer) {
    audioTimer = setInterval(checkAudio, 200);
    checkAudio();
  } else if (!audioSync && audioTimer) {
    clearInterval(audioTimer);
    audioTimer = null;
  }

  const instances = (currentState && currentState.instances && currentState.instances.length > 0)
    ? currentState.instances
    : [{
        id: 'default',
        sticker: null,
        x: 100,
        y: 100,
        scale: 1.0,
        flipped: false,
        isPaused: false,
        currentFrame: 0,
        w: BASE_SIZE,
        h: BASE_SIZE,
      }];

  const openStickerManagerHelper = (instId, currentSticker) => {
    const payload = JSON.stringify({
      mode: 'MANAGER',
      instanceId: instId,
      currentSticker: currentSticker || null,
    });
    const helperPath = '$HOME/Library/Application Support/Übersicht/widgets/sticker.widget/menu_helper';
    const fallbackPath = './sticker.widget/menu_helper';
    const escapedPayload = payload.replace(/'/g, "'\\''");
    const cmd = `"${helperPath}" '${escapedPayload}' 2>/dev/null || "${fallbackPath}" '${escapedPayload}' 2>/dev/null`;

    run(cmd, (err, output) => {
      if (err || !output) return;
      try {
        const res = JSON.parse(output.trim());
        if (!res || !res.action) return;
        if (res.action === 'SET_STICKER' && res.sticker) {
          dispatch({
            type: 'SET_STICKER',
            instanceId: res.instanceId || instId,
            sticker: res.sticker,
          });
        } else if (res.action === 'CLEAR_STICKER') {
          const st = res.sticker || currentSticker;
          if (st) {
            const filename = st.split('/').pop();
            const baseName = filename.replace(/\.[^/.]+$/, "");
            const deleteCmd = `rm -f "$HOME/Library/Application Support/Übersicht/widgets/sticker.widget/stickers/${baseName}"* "/Users/hhamelin/Documents/antigravity/uebersicht-sticker/sticker.widget/stickers/${baseName}"* 2>/dev/null`;
            run(deleteCmd);
          }
          dispatch({
            type: 'CLEAR_STICKER',
            instanceId: res.instanceId || instId,
            sticker: st,
          });
        }
      } catch (e) {}
    });
  };

  const handlePlusClick = (instanceId, e) => {
    if (e && e.stopPropagation) e.stopPropagation();
    const payload = JSON.stringify({
      mode: 'PLUS_CLICK',
      instanceId,
    });
    const helperPath = '$HOME/Library/Application Support/Übersicht/widgets/sticker.widget/menu_helper';
    const fallbackPath = './sticker.widget/menu_helper';
    const escapedPayload = payload.replace(/'/g, "'\\''");
    const cmd = `"${helperPath}" '${escapedPayload}' 2>/dev/null || "${fallbackPath}" '${escapedPayload}' 2>/dev/null`;

    run(cmd, (err, output) => {
      if (err || !output) return;
      try {
        const res = JSON.parse(output.trim());
        if (!res || !res.action) return;
        if (res.action === 'SET_STICKER' && res.sticker) {
          dispatch({
            type: 'SET_STICKER',
            instanceId: res.instanceId || instanceId,
            sticker: res.sticker,
          });
        } else if (res.action === 'OPEN_MANAGER') {
          openStickerManagerHelper(res.instanceId || instanceId, null);
        } else if (res.action === 'CLEAR_STICKER') {
          const st = res.sticker;
          if (st) {
            const filename = st.split('/').pop();
            const baseName = filename.replace(/\.[^/.]+$/, "");
            const deleteCmd = `rm -f "$HOME/Library/Application Support/Übersicht/widgets/sticker.widget/stickers/${baseName}"* "/Users/hhamelin/Documents/antigravity/uebersicht-sticker/sticker.widget/stickers/${baseName}"* 2>/dev/null`;
            run(deleteCmd);
          }
          dispatch({
            type: 'CLEAR_STICKER',
            instanceId: res.instanceId || instanceId,
            sticker: st,
          });
        }
      } catch (parseErr) {}
    });
  };

  const handleContextMenu = (instance, e) => {
    e.preventDefault();
    e.stopPropagation();

    const payload = JSON.stringify({
      mode: 'CONTEXT_MENU',
      instanceId: instance.id,
      currentSticker: instance.sticker || null,
      scale: instance.scale || 1.0,
      flipped: Boolean(instance.flipped),
      isPaused: Boolean(instance.isPaused),
      audioSync: Boolean(currentState.audioSync),
      opacity: opacity !== undefined ? opacity : 1.0,
      shadow: shadow !== false,
      enableSnapping: enableSnapping !== false,
      x: Math.round(instance.x),
      y: Math.round(instance.y),
    });

    const helperPath = '$HOME/Library/Application Support/Übersicht/widgets/sticker.widget/menu_helper';
    const fallbackPath = './sticker.widget/menu_helper';
    const escapedPayload = payload.replace(/'/g, "'\\''");
    const cmd = `"${helperPath}" '${escapedPayload}' 2>/dev/null || "${fallbackPath}" '${escapedPayload}' 2>/dev/null`;

    run(cmd, (err, output) => {
      if (err || !output) return;
      try {
        const res = JSON.parse(output.trim());
        if (!res || !res.action) return;

        if (res.action === 'SET_STICKER') {
          dispatch({
            type: 'SET_STICKER',
            instanceId: res.instanceId || instance.id,
            sticker: res.sticker,
          });
        } else if (res.action === 'CLEAR_FROM_WIDGET') {
          dispatch({
            type: 'CLEAR_FROM_WIDGET',
            instanceId: res.instanceId || instance.id,
          });
        } else if (res.action === 'CLEAR_STICKER') {
          const st = res.sticker || instance.sticker;
          if (st) {
            const filename = st.split('/').pop();
            const baseName = filename.replace(/\.[^/.]+$/, "");
            const deleteCmd = `rm -f "$HOME/Library/Application Support/Übersicht/widgets/sticker.widget/stickers/${baseName}"* "/Users/hhamelin/Documents/antigravity/uebersicht-sticker/sticker.widget/stickers/${baseName}"* 2>/dev/null`;
            run(deleteCmd);
          }
          dispatch({
            type: 'CLEAR_STICKER',
            instanceId: res.instanceId || instance.id,
            sticker: st,
          });
        } else if (res.action === 'OPEN_MANAGER') {
          openStickerManagerHelper(res.instanceId || instance.id, instance.sticker);
        } else if (res.action === 'SET_SCALE') {
          dispatch({
            type: 'SET_SCALE',
            instanceId: res.instanceId || instance.id,
            scale: res.scale,
          });
        } else if (res.action === 'SET_FLIP') {
          dispatch({
            type: 'SET_FLIP',
            instanceId: res.instanceId || instance.id,
            flipped: res.flipped,
          });
        } else if (res.action === 'TOGGLE_PAUSE') {
          const targetInstId = res.instanceId || instance.id;
          dispatch({ type: 'TOGGLE_PAUSE', instanceId: targetInstId });
        } else if (res.action === 'TOGGLE_AUDIO_SYNC') {
          dispatch({ type: 'TOGGLE_AUDIO_SYNC' });
        } else if (res.action === 'SET_OPACITY') {
          dispatch({ type: 'SET_OPACITY', opacity: res.opacity });
        } else if (res.action === 'TOGGLE_SHADOW') {
          dispatch({ type: 'TOGGLE_SHADOW' });
        } else if (res.action === 'TOGGLE_SNAPPING') {
          dispatch({ type: 'TOGGLE_SNAPPING' });
        } else if (res.action === 'RESET_POSITION') {
          dispatch({ type: 'RESET_POSITION', instanceId: res.instanceId || instance.id });
        } else if (res.action === 'RELOAD_WIDGET') {
          const wid = res.widgetId || 'sticker-widget-index-jsx';
          run(`osascript -e 'tell application id "tracesOf.Uebersicht" to reload widget id "${wid}"' 2>/dev/null || osascript -e 'tell application id "tracesOf.Uebersicht" to refresh'`);
        } else if (res.action === 'REMOVE_WIDGET') {
          dispatch({ type: 'REMOVE_WIDGET', instanceId: res.instanceId || instance.id, widgetId: res.widgetId || 'sticker-widget-index-jsx' });
        } else if (res.action === 'DUPLICATE_WIDGET') {
          dispatch({ type: 'DUPLICATE_WIDGET', instanceId: res.instanceId || instance.id });
        } else if (res.action === 'ORDER_FRONT' || res.action === 'ORDER_FORWARD' || res.action === 'ORDER_BACKWARD' || res.action === 'ORDER_BACK') {
          reorderWidget('sticker', res.action);
          dispatch({ type: 'ORDER_CHANGED' });
        }
      } catch (parseErr) {}
    });
  };

  if (typeof window !== 'undefined') {
    setTimeout(() => {
      instances.forEach((inst) => {
        if (inst.sticker) {
          const cur = animFrameState[inst.id]?.currentFrame ?? inst.currentFrame ?? 0;
          drawCanvasFrame(inst.id, inst.sticker, cur);
        }
      });
    }, 0);
  }

  return (
    <div className="sticker-root">
      {instances.map((instance) => {
        const hasSticker = Boolean(instance.sticker);
        const meta = hasSticker ? stickerMetaCache[instance.sticker] : null;

        if (hasSticker && !meta) {
          loadStickerMeta(instance.sticker, (loadedMeta) => {
            if (loadedMeta && (!instance.w || !instance.h)) {
              const aspect = loadedMeta.width / loadedMeta.height;
              let fitW = BASE_SIZE;
              let fitH = BASE_SIZE;
              if (aspect >= 1) {
                fitH = Math.round(BASE_SIZE / aspect);
              } else {
                fitW = Math.round(BASE_SIZE * aspect);
              }
              dispatch({
                type: 'SET_NATURAL_SIZE',
                instanceId: instance.id,
                w: fitW,
                h: fitH,
              });
            }
            const cur = animFrameState[instance.id]?.currentFrame ?? instance.currentFrame ?? 0;
            drawCanvasFrame(instance.id, instance.sticker, cur);
          });
        } else if (hasSticker && meta && (!instance.w || !instance.h) && meta.width && meta.height) {
          const aspect = meta.width / meta.height;
          let fitW = BASE_SIZE;
          let fitH = BASE_SIZE;
          if (aspect >= 1) {
            fitH = Math.round(BASE_SIZE / aspect);
          } else {
            fitW = Math.round(BASE_SIZE * aspect);
          }
          dispatch({
            type: 'SET_NATURAL_SIZE',
            instanceId: instance.id,
            w: fitW,
            h: fitH,
          });
        }

        const instScale = instance.scale ?? 1.0;
        const instCardW = hasSticker
          ? Math.round((instance.w || BASE_SIZE) * instScale)
          : BLANK_SQUARE_SIZE;
        const instCardH = hasSticker
          ? Math.round((instance.h || BASE_SIZE) * instScale)
          : BLANK_SQUARE_SIZE;
        const instFlipped = Boolean(instance.flipped);
        const x = instance.x ?? 100;
        const y = instance.y ?? 100;
        const isDragging = currentState.isDragging && currentState.draggingInstanceId === instance.id;

        const handleMouseDown = (e) => {
          if (e.button !== 0) return; // Only primary mouse button

          const now = Date.now();
          if (hasSticker) {
            const isDoubleClick = now - lastClickTimestamp < 320;
            lastClickTimestamp = now;

            if (isDoubleClick) {
              e.preventDefault();
              dispatch({ type: 'TOGGLE_FLIP', instanceId: instance.id });
              return;
            }
          }

          const startX = e.clientX;
          const startY = e.clientY;
          let hasMoved = false;

          const handleMouseMove = (moveEvent) => {
            const dx = moveEvent.clientX - startX;
            const dy = moveEvent.clientY - startY;

            if (!hasMoved) {
              if (Math.hypot(dx, dy) > 4) {
                hasMoved = true;
                dispatch({
                  type: 'START_DRAG',
                  instanceId: instance.id,
                  clientX: startX,
                  clientY: startY,
                  startPosX: x,
                  startPosY: y,
                  w: instCardW,
                  h: instCardH,
                });
              }
            }

            if (hasMoved) {
              moveEvent.preventDefault();
              dispatch({
                type: 'MOVE_DRAG',
                clientX: moveEvent.clientX,
                clientY: moveEvent.clientY,
                bypassSnap: moveEvent.metaKey || moveEvent.altKey || moveEvent.shiftKey,
              });
            }
          };

          const handleMouseUp = () => {
            window.removeEventListener('mousemove', handleMouseMove);
            window.removeEventListener('mouseup', handleMouseUp);
            if (hasMoved) {
              dispatch({ type: 'END_DRAG' });
            } else if (!hasSticker) {
              // Clicked without dragging on blank square: open picker / menu!
              handlePlusClick(instance.id, e);
            }
          };

          window.addEventListener('mousemove', handleMouseMove);
          window.addEventListener('mouseup', handleMouseUp);
        };

        const containerStyle = {
          position: 'absolute',
          top: `${y}px`,
          left: `${x}px`,
          width: `${instCardW}px`,
          height: `${instCardH}px`,
          boxSizing: 'border-box',
          zIndex: isDragging ? 9999 : getWidgetZIndex('sticker'),
          pointerEvents: hasSticker ? 'none' : 'auto',
          userSelect: 'none',
          WebkitUserSelect: 'none',
        };

        const blankSquareStyle = {
          width: `${BLANK_SQUARE_SIZE}px`,
          height: `${BLANK_SQUARE_SIZE}px`,
          background: 'rgba(28, 27, 25, 0.75)',
          backdropFilter: 'blur(25px)',
          WebkitBackdropFilter: 'blur(25px)',
          borderRadius: '16px',
          border: '1px solid rgba(255, 255, 255, 0.12)',
          boxShadow: '0 8px 32px rgba(0, 0, 0, 0.35)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          cursor: isDragging ? 'grabbing' : 'pointer',
          boxSizing: 'border-box',
          pointerEvents: 'auto',
        };

        const stickerStyle = {
          position: 'relative',
          width: '100%',
          height: '100%',
          pointerEvents: 'auto',
          cursor: isDragging ? 'grabbing' : 'grab',
          transform: instFlipped ? 'scaleX(-1)' : 'none',
          opacity: opacity,
          transition: isDragging ? 'none' : 'opacity 0.2s ease, transform 0.2s cubic-bezier(0.34, 1.56, 0.64, 1)',
        };

        return (
          <div
            key={instance.id}
            id={`sticker-container-${instance.id}`}
            style={containerStyle}
            onContextMenu={(e) => handleContextMenu(instance, e)}
          >
            {!hasSticker ? (
              /* Blank Square Placeholder with Large Off-White Plus Sign */
              <div
                className="sticker-blank-square"
                style={blankSquareStyle}
                onMouseDown={handleMouseDown}
                title="Click to select WebP Sticker (or drag to position)"
              >
                <svg
                  className="sticker-plus-icon"
                  width="42"
                  height="42"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="rgba(242, 242, 247, 0.82)"
                  strokeWidth="2.3"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  style={{
                    pointerEvents: 'none',
                    filter: 'drop-shadow(0 2px 4px rgba(0,0,0,0.3))',
                    transition: 'stroke 0.15s ease, transform 0.15s ease',
                  }}
                >
                  <line x1="12" y1="5" x2="12" y2="19" />
                  <line x1="5" y1="12" x2="19" y2="12" />
                </svg>
              </div>
            ) : (
              /* Active WebP Sticker Box */
              <div
                id={`sticker-interactive-${instance.id}`}
                style={stickerStyle}
                onMouseDown={handleMouseDown}
                title="Sticker (Drag to move, Double-click to flip, Right-click for options)"
              >
                <canvas
                  id={`sticker-canvas-${instance.id}`}
                  width={Math.round((instCardW + SHADOW_PAD * 2) * (typeof window !== 'undefined' ? (window.devicePixelRatio || 1) : 1))}
                  height={Math.round((instCardH + SHADOW_PAD * 2) * (typeof window !== 'undefined' ? (window.devicePixelRatio || 1) : 1))}
                  style={{
                    position: 'absolute',
                    top: `-${SHADOW_PAD}px`,
                    left: `-${SHADOW_PAD}px`,
                    width: `${instCardW + SHADOW_PAD * 2}px`,
                    height: `${instCardH + SHADOW_PAD * 2}px`,
                    pointerEvents: 'none',
                    userSelect: 'none',
                    WebkitUserSelect: 'none',
                    imageRendering: '-webkit-optimize-contrast',
                  }}
                />
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
};

export const className = `
  font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro Display", "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
  color: #ffffff;

  .sticker-blank-square {
    transition: transform 0.16s ease, border-color 0.16s ease, box-shadow 0.16s ease;
  }
  .sticker-blank-square:hover {
    border-color: rgba(255, 255, 255, 0.28) !important;
    box-shadow: 0 12px 36px rgba(0, 0, 0, 0.45), 0 0 0 1px rgba(255, 255, 255, 0.1) inset !important;
    transform: scale(1.03);
  }
  .sticker-blank-square:hover .sticker-plus-icon {
    stroke: rgba(255, 255, 255, 1) !important;
    transform: scale(1.08);
  }
  .sticker-blank-square:active {
    transform: scale(0.97);
  }
`;
