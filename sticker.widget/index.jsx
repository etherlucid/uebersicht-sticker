import { React, run } from 'uebersicht';
import {
  getWidgetZIndex,
  reorderWidget,
  getScreenId,
  resolveActiveScreen,
  isScreenActive,
  calculateSnappedPosition,
  computeCrossScreenPreview,
  resolveDragEndAcrossScreens,
  broadcastWidgetMessage,
  initWidgetDesktopSync,
} from './lib/desktop.js';

export const refreshFrequency = false;
export const command = 'cat "$HOME/Library/Application Support/Übersicht/widgets/sticker.widget/.pending_action" 2>/dev/null || true';

const BLANK_SQUARE_SIZE = 100;
const BASE_SIZE = 180;
const SHADOW_PAD = 24;

const STORAGE_INSTANCES_KEY = 'sticker_widget_instances';
const STORAGE_OPACITY_KEY = 'sticker_widget_opacity';
const STORAGE_SHADOW_KEY = 'sticker_widget_shadow';
const STORAGE_SNAP_KEY = 'sticker_widget_snapping';
const STORAGE_AUDIO_SYNC_KEY = 'sticker_widget_audio_sync';
const STORAGE_HIDDEN_PLUS_KEY = 'sticker_widget_hidden_plus_screens';

const SNAP_MARGIN_X = 15;
const SNAP_MARGIN_TOP = 14;

let lastClickTimestamp = 0;
let lastContextMenuTimestamp = 0;
let lastPlusClickTimestamp = 0;
let audioTimer = null;
let isCheckingAudio = false;
let activePlayingTicks = {};
const DEFAULT_AUDIO_SENSITIVITY = 20;

const debugLog = () => {};
let currentDispatch = null;
let currentWidgetState = null;

const getHelperCmd = (payload) => {
  const escapedPayload = payload.replace(/'/g, "'\\''");
  const appHelper = '$HOME/Library/Application Support/Übersicht/widgets/sticker.widget/StickerManager.app/Contents/MacOS/menu_helper';
  const appFallback = './sticker.widget/StickerManager.app/Contents/MacOS/menu_helper';
  const helperPath = '$HOME/Library/Application Support/Übersicht/widgets/sticker.widget/menu_helper';
  const fallbackPath = './sticker.widget/menu_helper';
  return `"${appHelper}" '${escapedPayload}' 2>/dev/null || "${appFallback}" '${escapedPayload}' 2>/dev/null || "${helperPath}" '${escapedPayload}' 2>/dev/null || "${fallbackPath}" '${escapedPayload}' 2>/dev/null`;
};

// Sprite Sheet Animation Engine
const stickerMetaCache = {};
const metaLoadingMap = {};
const sheetImageCache = {};
const animFrameState = {};
let globalRafId = null;

const loadStickerMeta = (stickerPath, callback) => {
  if (!stickerPath) return;
  if (stickerMetaCache[stickerPath]) {
    if (callback) callback(stickerMetaCache[stickerPath]);
    return;
  }
  if (metaLoadingMap[stickerPath]) {
    if (callback) metaLoadingMap[stickerPath].push(callback);
    return;
  }
  metaLoadingMap[stickerPath] = callback ? [callback] : [];

  const filename = stickerPath.split('/').pop();
  const scriptPath = '$HOME/Library/Application Support/Übersicht/widgets/sticker.widget/sheet_generator.py';
  const stickersDir = '$HOME/Library/Application Support/Übersicht/widgets/sticker.widget/stickers';
  const fallbackScript = './sticker.widget/sheet_generator.py';
  const fallbackStickers = './sticker.widget/stickers';

  const cmd = `"/usr/bin/python3" "${scriptPath}" "${stickersDir}/${filename}" "${stickersDir}" 2>/dev/null || "/usr/bin/python3" "${fallbackScript}" "${fallbackStickers}/${filename}" "${fallbackStickers}" 2>/dev/null`;

  run(cmd, (err, output) => {
    const callbacks = metaLoadingMap[stickerPath] || [];
    delete metaLoadingMap[stickerPath];
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
        callbacks.forEach((cb) => {
          try { cb(meta); } catch (e) {}
        });
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

  const inst = currentWidgetState?.instances?.find((i) => i.id === instanceId);
  if (inst && inst.sticker && inst.sticker !== stickerPath) {
    return;
  }

  const ctx = canvas.getContext('2d');
  if (!ctx) return;

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
  const showShadow = inst?.shadow !== false && !isDragging;

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
      const instScale = inst.scale ?? 1.0;
      const shadowKey = `${inst.sticker}_${instScale}_${inst.shadow !== false}`;
      if (!animFrameState[inst.id] || animFrameState[inst.id].staticKey !== shadowKey) {
        animFrameState[inst.id] = {
          currentFrame: 0,
          lastFrameTimestamp: now,
          staticKey: shadowKey,
        };
        drawCanvasFrame(inst.id, inst.sticker, 0);
      }
      return;
    }

    if (!animFrameState[inst.id] || animFrameState[inst.id].stickerPath !== inst.sticker) {
      animFrameState[inst.id] = {
        stickerPath: inst.sticker,
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
  if (!currentWidgetState || !currentDispatch) return;

  const instances = currentWidgetState.instances || [];
  const audioSyncInstances = instances.filter((inst) => inst.sticker && inst.audioSync);
  if (audioSyncInstances.length === 0) return;

  isCheckingAudio = true;
  const audioCheckPath = '$HOME/Library/Application Support/Übersicht/widgets/sticker.widget/audio_check';
  const fallbackPath = './sticker.widget/audio_check';
  const cmd = `"${audioCheckPath}" 2>/dev/null || "${fallbackPath}" 2>/dev/null`;

  run(cmd, (err, output) => {
    isCheckingAudio = false;
    if (err || !output) return;
    const rawVal = parseInt(output.trim(), 10);
    const currentAudioLevel = isNaN(rawVal) ? 0 : rawVal;

    const now = Date.now();
    let anyStateChanged = false;

    const updatedInstances = (currentWidgetState.instances || []).map((inst) => {
      if (inst.sticker && inst.audioSync) {
        const threshold = (typeof inst.audioSensitivity === 'number' && inst.audioSensitivity > 0)
          ? inst.audioSensitivity
          : DEFAULT_AUDIO_SENSITIVITY;

        if (currentAudioLevel >= threshold) {
          activePlayingTicks[inst.id] = now;
        }

        // 350ms grace release period to avoid stuttering on musical pauses / drops
        const isPlaying = (currentAudioLevel >= threshold) || ((now - (activePlayingTicks[inst.id] || 0)) < 350);

        if (isPlaying ? inst.isPaused : !inst.isPaused) {
          anyStateChanged = true;
          if (isPlaying && inst.isPaused && animFrameState[inst.id]) {
            animFrameState[inst.id].lastFrameTimestamp = performance.now();
          }
          return {
            ...inst,
            isPaused: !isPlaying,
            currentFrame: animFrameState[inst.id]?.currentFrame ?? inst.currentFrame ?? 0,
          };
        }
      }
      return inst;
    });

    if (anyStateChanged) {
      currentDispatch({ type: 'AUDIO_LEVEL_TICK', instances: updatedInstances });
    }
  });
};

const getInitialPosition = () => {
  return {
    x: SNAP_MARGIN_X,
    y: SNAP_MARGIN_TOP,
  };
};

const getInitialInstances = () => {
  try {
    const saved = typeof localStorage !== 'undefined' ? localStorage.getItem(STORAGE_INSTANCES_KEY) : null;
    if (saved) {
      const parsed = JSON.parse(saved);
      if (Array.isArray(parsed) && parsed.length > 0) {
        return parsed.map((inst) => ({
          ...inst,
          targetScreen: resolveActiveScreen(inst.targetScreen || 'screen_1'),
          audioSensitivity: typeof inst.audioSensitivity === 'number' ? inst.audioSensitivity : DEFAULT_AUDIO_SENSITIVITY,
        }));
      }
    }

    const screen1Saved = typeof localStorage !== 'undefined' ? localStorage.getItem(`${STORAGE_INSTANCES_KEY}_screen_1`) : null;
    if (screen1Saved) {
      const parsed1 = JSON.parse(screen1Saved);
      if (Array.isArray(parsed1) && parsed1.length > 0) {
        const migrated = parsed1.map((inst) => ({
          ...inst,
          targetScreen: resolveActiveScreen(inst.targetScreen || 'screen_1'),
          audioSensitivity: typeof inst.audioSensitivity === 'number' ? inst.audioSensitivity : DEFAULT_AUDIO_SENSITIVITY,
        }));
        localStorage.setItem(STORAGE_INSTANCES_KEY, JSON.stringify(migrated));
        return migrated;
      }
    }
  } catch (e) {}

  const defaultPos = getInitialPosition();
  return [{
    id: 'default',
    sticker: null,
    targetScreen: resolveActiveScreen('screen_1'),
    x: defaultPos.x,
    y: defaultPos.y,
    scale: 1.0,
    flipped: false,
    isPaused: false,
    currentFrame: 0,
    w: BASE_SIZE,
    h: BASE_SIZE,
    audioSync: false,
    audioSensitivity: DEFAULT_AUDIO_SENSITIVITY,
  }];
};

const saveInstances = (instances) => {
  const screenId = getScreenId();
  try {
    localStorage.setItem(STORAGE_INSTANCES_KEY, JSON.stringify(instances));
    localStorage.setItem(`${STORAGE_INSTANCES_KEY}_${screenId}`, JSON.stringify(instances));
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

const getHiddenPlusScreens = () => {
  try {
    const saved = typeof localStorage !== 'undefined' ? localStorage.getItem(STORAGE_HIDDEN_PLUS_KEY) : null;
    if (saved) {
      const parsed = JSON.parse(saved);
      if (Array.isArray(parsed)) return parsed;
    }
  } catch (e) {}
  return [];
};

const saveHiddenPlusScreens = (screens) => {
  try {
    localStorage.setItem(STORAGE_HIDDEN_PLUS_KEY, JSON.stringify(screens));
  } catch (e) {}
};

const initialInstances = getInitialInstances();

export const initialState = {
  instances: initialInstances,
  hiddenPlusScreens: getHiddenPlusScreens(),
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
  crossScreenPreview: null,
};

export const updateState = (event, previousState) => {
  if (!previousState) return initialState;
  if (event && event.output) {
    try {
      const parsed = JSON.parse(event.output.trim());
      if (parsed && (parsed.action || parsed.type)) {
        event = { type: parsed.action || parsed.type, ...parsed };
      }
    } catch (e) {}
  }

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
      previousState.enableSnapping,
      true
    );

    const updatedInstances = (previousState.instances || []).map((inst) => {
      if (inst.id === previousState.draggingInstanceId) {
        return { ...inst, x: newX, y: newY };
      }
      return inst;
    });

    return {
      ...previousState,
      instances: updatedInstances,
    };
  }

  if (event.type === 'END_DRAG') {
    const draggingId = previousState.draggingInstanceId;
    const currentInst = (previousState.instances || []).find((i) => i.id === draggingId);
    if (!currentInst) {
      return {
        ...previousState,
        isDragging: false,
        draggingInstanceId: null,
        crossScreenPreview: null,
      };
    }

    const cardW = previousState.startW || BLANK_SQUARE_SIZE;
    const cardH = previousState.startH || BLANK_SQUARE_SIZE;
    const curX = currentInst.x ?? 0;
    const curY = currentInst.y ?? 0;
    const currentScreenId = getScreenId();

    const { targetScreen, x: finalX, y: finalY } = resolveDragEndAcrossScreens(
      currentScreenId,
      curX,
      curY,
      cardW,
      cardH
    );

    const updatedInstances = (previousState.instances || []).map((inst) => {
      if (inst.id === draggingId) {
        return { ...inst, targetScreen, x: finalX, y: finalY };
      }
      return inst;
    });

    saveInstances(updatedInstances);

    broadcastWidgetMessage('sticker', {
      type: 'CROSS_SCREEN_DRAG_PREVIEW',
      preview: null,
    });
    broadcastWidgetMessage('sticker', {
      type: 'SYNC_INSTANCES',
      instances: updatedInstances,
    });

    return {
      ...previousState,
      isDragging: false,
      draggingInstanceId: null,
      crossScreenPreview: null,
      instances: updatedInstances,
    };
  }

  if (event.type === 'CROSS_SCREEN_DRAG_PREVIEW') {
    return {
      ...previousState,
      crossScreenPreview: event.preview || null,
    };
  }

  if (event.type === 'SYNC_INSTANCES') {
    return {
      ...previousState,
      instances: event.instances,
    };
  }

  if (event.type === 'DISPLAY_TOPOLOGY_CHANGED') {
    const updated = (previousState.instances || []).map((inst) => ({
      ...inst,
      targetScreen: resolveActiveScreen(inst.targetScreen || 'screen_1'),
    }));
    saveInstances(updated);
    return {
      ...previousState,
      instances: updated,
      topologyTick: Date.now(),
    };
  }

  if (event.type === 'COLLAPSE_TO_SINGLE_SCREEN') {
    const primaryScreen = event.screenId || resolveActiveScreen('screen_0');
    let changed = false;
    const updated = (previousState.instances || []).map((inst) => {
      if (inst.targetScreen && inst.targetScreen !== primaryScreen) {
        changed = true;
        return { ...inst, targetScreen: primaryScreen };
      }
      return inst;
    });
    if (changed) {
      saveInstances(updated);
      broadcastWidgetMessage('sticker', {
        type: 'SYNC_INSTANCES',
        instances: updated,
      });
      return {
        ...previousState,
        instances: updated,
      };
    }
    return previousState;
  }

  if (event.type === 'MOVE_TO_SCREEN') {
    const targetId = event.instanceId;
    const targetScreen = resolveActiveScreen(event.screenId || 'screen_1');
    const updated = (previousState.instances || []).map((inst) => {
      if (inst.id === targetId) {
        return { ...inst, targetScreen, x: SNAP_MARGIN_X, y: SNAP_MARGIN_TOP };
      }
      return inst;
    });
    saveInstances(updated);
    broadcastWidgetMessage('sticker', {
      type: 'SYNC_INSTANCES',
      instances: updated,
    });
    return {
      ...previousState,
      instances: updated,
    };
  }

  if (event.type === 'HIDE_PLUS_ON_SCREEN') {
    const sid = resolveActiveScreen(event.screenId || getScreenId());
    const current = previousState.hiddenPlusScreens || [];
    if (!current.includes(sid)) {
      const updated = [...current, sid];
      saveHiddenPlusScreens(updated);
      broadcastWidgetMessage('sticker', {
        type: 'SYNC_HIDDEN_PLUS',
        hiddenPlusScreens: updated,
      });
      return {
        ...previousState,
        hiddenPlusScreens: updated,
      };
    }
    return previousState;
  }

  if (event.type === 'TOGGLE_SHOW_PLUS') {
    const sid = resolveActiveScreen(event.screenId || getScreenId());
    const current = previousState.hiddenPlusScreens || [];
    let updated;
    if (current.includes(sid)) {
      updated = current.filter((s) => s !== sid);
    } else {
      updated = [...current, sid];
    }
    saveHiddenPlusScreens(updated);
    broadcastWidgetMessage('sticker', {
      type: 'SYNC_HIDDEN_PLUS',
      hiddenPlusScreens: updated,
    });
    return {
      ...previousState,
      hiddenPlusScreens: updated,
    };
  }

  if (event.type === 'SYNC_HIDDEN_PLUS') {
    return {
      ...previousState,
      hiddenPlusScreens: event.hiddenPlusScreens || [],
    };
  }

  if (event.type === 'SET_STICKER') {
    const targetId = event.instanceId;
    delete animFrameState[targetId];

    const meta = stickerMetaCache[event.sticker];
    let initialW = null;
    let initialH = null;
    if (meta && meta.width && meta.height) {
      const aspect = meta.width / meta.height;
      if (aspect >= 1) {
        initialH = Math.round(BASE_SIZE / aspect);
        initialW = BASE_SIZE;
      } else {
        initialW = Math.round(BASE_SIZE * aspect);
        initialH = BASE_SIZE;
      }
    }
    const curScreenId = getScreenId();
    const isBlankPlaceholder = Boolean(targetId && targetId.startsWith('blank_'));
    const hasTarget = (previousState.instances || []).some((i) => i.id === targetId);

    let updatedInstances;
    let effectiveTargetId = targetId;

    if (isBlankPlaceholder || !hasTarget) {
      effectiveTargetId = `inst_${Date.now()}_${Math.random().toString(36).substr(2, 4)}`;
      const newInst = {
        id: effectiveTargetId,
        targetScreen: resolveActiveScreen(curScreenId),
        sticker: event.sticker,
        x: SNAP_MARGIN_X,
        y: SNAP_MARGIN_TOP,
        scale: 1.0,
        flipped: false,
        isPaused: false,
        currentFrame: 0,
        w: initialW || BASE_SIZE,
        h: initialH || BASE_SIZE,
        audioSync: false,
        audioSensitivity: DEFAULT_AUDIO_SENSITIVITY,
      };
      updatedInstances = [...(previousState.instances || []), newInst];
    } else {
      updatedInstances = (previousState.instances || []).map((inst) => {
        if (inst.id === targetId || (!targetId && inst.id === (previousState.instances?.[0]?.id || 'default'))) {
          return {
            ...inst,
            targetScreen: resolveActiveScreen(inst.targetScreen || curScreenId),
            sticker: event.sticker,
            isPaused: false,
            currentFrame: 0,
            w: initialW || null,
            h: initialH || null,
          };
        }
        return inst;
      });
    }

    saveInstances(updatedInstances);

    broadcastWidgetMessage('sticker', {
      type: 'SYNC_INSTANCES',
      instances: updatedInstances,
    });

    if (!meta) {
      loadStickerMeta(event.sticker, (loadedMeta) => {
        if (loadedMeta && loadedMeta.width && loadedMeta.height) {
          const aspect = loadedMeta.width / loadedMeta.height;
          let fitW = BASE_SIZE;
          let fitH = BASE_SIZE;
          if (aspect >= 1) {
            fitH = Math.round(BASE_SIZE / aspect);
          } else {
            fitW = Math.round(BASE_SIZE * aspect);
          }
          if (currentDispatch) {
            currentDispatch({
              type: 'SET_NATURAL_SIZE',
              instanceId: effectiveTargetId,
              w: fitW,
              h: fitH,
            });
          }
        }
      });
    }

    return {
      ...previousState,
      instances: updatedInstances,
    };
  }

  if (event.type === 'RESET_TO_BLANK_PLUS') {
    Object.keys(animFrameState).forEach((k) => delete animFrameState[k]);
    const defaultPos = getInitialPosition();
    const blankInstances = [{
      id: 'default',
      sticker: null,
      targetScreen: resolveActiveScreen(getScreenId()),
      x: defaultPos.x,
      y: defaultPos.y,
      scale: 1.0,
      flipped: false,
      isPaused: false,
      currentFrame: 0,
      w: BASE_SIZE,
      h: BASE_SIZE,
    }];
    saveInstances(blankInstances);
    return {
      ...previousState,
      instances: blankInstances,
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
    broadcastWidgetMessage('sticker', {
      type: 'SYNC_INSTANCES',
      instances: updatedInstances,
    });
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
    broadcastWidgetMessage('sticker', {
      type: 'SYNC_INSTANCES',
      instances: updatedInstances,
    });
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
    const targetId = event.instanceId;
    const updatedInstances = (previousState.instances || []).map((inst) => {
      if (inst.id === targetId || (!targetId && inst.id === (previousState.instances?.[0]?.id || 'default'))) {
        const nextSync = !inst.audioSync;
        return {
          ...inst,
          audioSync: nextSync,
          isPaused: nextSync ? inst.isPaused : false,
        };
      }
      return inst;
    });
    saveInstances(updatedInstances);
    setTimeout(checkAudio, 10);
    return {
      ...previousState,
      instances: updatedInstances,
    };
  }

  if (event.type === 'AUDIO_LEVEL_TICK') {
    const updatedInstances = event.instances || [];
    saveInstances(updatedInstances);
    return {
      ...previousState,
      instances: updatedInstances,
    };
  }

  if (event.type === 'SET_AUDIO_SENSITIVITY') {
    const nextSens = event.audioSensitivity;
    const targetId = event.instanceId;
    const updatedInstances = (previousState.instances || []).map((inst) => {
      if (!targetId || inst.id === targetId) {
        return { ...inst, audioSensitivity: nextSens };
      }
      return inst;
    });
    saveInstances(updatedInstances);
    setTimeout(checkAudio, 10);
    return {
      ...previousState,
      instances: updatedInstances,
    };
  }

  if (event.type === 'AUDIO_STATUS_CHANGED') {
    const isPlaying = event.isPlaying;
    const updatedInstances = (previousState.instances || []).map((inst) => {
      if (inst.sticker && inst.audioSync) {
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
    const targetId = event.instanceId;
    const updatedInstances = (previousState.instances || []).map((inst) => {
      if (inst.id === targetId || (!targetId && inst.id === (previousState.instances?.[0]?.id || 'default'))) {
        return { ...inst, opacity: event.opacity };
      }
      return inst;
    });
    saveInstances(updatedInstances);
    return {
      ...previousState,
      instances: updatedInstances,
    };
  }

  if (event.type === 'TOGGLE_SHADOW') {
    const targetId = event.instanceId;
    const updatedInstances = (previousState.instances || []).map((inst) => {
      if (inst.id === targetId || (!targetId && inst.id === (previousState.instances?.[0]?.id || 'default'))) {
        return {
          ...inst,
          shadow: inst.shadow === false ? true : false,
        };
      }
      return inst;
    });
    saveInstances(updatedInstances);
    setTimeout(() => {
      const target = updatedInstances.find((i) => i.id === targetId);
      if (target && target.sticker) {
        drawCanvasFrame(targetId, target.sticker, animFrameState[targetId]?.currentFrame ?? 0);
      }
    }, 0);
    return {
      ...previousState,
      instances: updatedInstances,
    };
  }

  if (event.type === 'ORDER_FRONT' || event.type === 'ORDER_FORWARD' || event.type === 'ORDER_BACKWARD' || event.type === 'ORDER_BACK') {
    const targetId = event.instanceId;
    const updatedInstances = [...(previousState.instances || [])];
    const idx = updatedInstances.findIndex((i) => i.id === targetId);

    if (idx !== -1) {
      const [target] = updatedInstances.splice(idx, 1);
      if (event.type === 'ORDER_FRONT') {
        updatedInstances.push(target);
      } else if (event.type === 'ORDER_BACK') {
        updatedInstances.unshift(target);
      } else if (event.type === 'ORDER_FORWARD') {
        const nextIdx = Math.min(updatedInstances.length, idx + 1);
        updatedInstances.splice(nextIdx, 0, target);
      } else if (event.type === 'ORDER_BACKWARD') {
        const prevIdx = Math.max(0, idx - 1);
        updatedInstances.splice(prevIdx, 0, target);
      }
      saveInstances(updatedInstances);
    }

    reorderWidget('sticker', event.type);

    return {
      ...previousState,
      instances: updatedInstances,
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
    const targetId = event.instanceId;
    const defaultX = SNAP_MARGIN_X;
    const defaultY = SNAP_MARGIN_TOP;

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

  if (event.type === 'ADD_STICKER_INSTANCE') {
    const curScreenId = getScreenId();
    const resolvedTarget = resolveActiveScreen(
      event.targetScreen || (event.targetScreenNum ? `screen_${event.targetScreenNum}` : null) || event.targetResolution || curScreenId
    );

    if (!isScreenActive(curScreenId, resolvedTarget)) {
      return previousState;
    }

    if (event.actionId && previousState.lastActionId === event.actionId) {
      return previousState;
    }

    const current = previousState.instances || [];
    const defaultPos = getInitialPosition();

    let updatedInstances;
    let newInstId = 'default';
    if (current.length === 1 && !current[0].sticker) {
      newInstId = current[0].id || 'default';
      updatedInstances = [{
        ...current[0],
        targetScreen: resolvedTarget,
        sticker: event.sticker,
        x: defaultPos.x,
        y: defaultPos.y,
        scale: 1.0,
        flipped: false,
        isPaused: false,
        currentFrame: 0,
        w: BASE_SIZE,
        h: BASE_SIZE,
        audioSync: false,
        audioSensitivity: DEFAULT_AUDIO_SENSITIVITY,
      }];
    } else {
      let posX = defaultPos.x;
      let posY = defaultPos.y;
      const exactMatch = current.some((i) => Math.abs((i.x ?? 0) - posX) < 15 && Math.abs((i.y ?? 0) - posY) < 15);
      if (exactMatch) {
        posX += 30;
        posY += 30;
      }

      newInstId = `inst_${Date.now()}_${Math.random().toString(36).substr(2, 4)}`;
      const newInst = {
        id: newInstId,
        targetScreen: resolvedTarget,
        sticker: event.sticker,
        x: posX,
        y: posY,
        scale: 1.0,
        flipped: false,
        isPaused: false,
        currentFrame: 0,
        w: BASE_SIZE,
        h: BASE_SIZE,
        audioSync: false,
        audioSensitivity: DEFAULT_AUDIO_SENSITIVITY,
      };
      updatedInstances = [...current, newInst];
    }

    saveInstances(updatedInstances);
    broadcastWidgetMessage('sticker', {
      type: 'SYNC_INSTANCES',
      instances: updatedInstances,
    });

    loadStickerMeta(event.sticker, (loadedMeta) => {
      if (loadedMeta && loadedMeta.width && loadedMeta.height) {
        const aspect = loadedMeta.width / loadedMeta.height;
        let fitW = BASE_SIZE;
        let fitH = BASE_SIZE;
        if (aspect >= 1) {
          fitH = Math.round(BASE_SIZE / aspect);
        } else {
          fitW = Math.round(BASE_SIZE * aspect);
        }
        if (currentDispatch) {
          currentDispatch({
            type: 'SET_NATURAL_SIZE',
            instanceId: newInstId,
            w: fitW,
            h: fitH,
          });
        }
      }
    });

    return {
      ...previousState,
      instances: updatedInstances,
      lastActionId: event.actionId || null,
    };
  }

  if (event.type === 'DUPLICATE_WIDGET') {
    const curScreenId = getScreenId();
    const current = previousState.instances && previousState.instances.length > 0
      ? previousState.instances
      : [{ id: 'default', x: 100, y: 100, scale: 1.0, flipped: false, sticker: null }];
    const target = current.find((i) => i.id === event.instanceId) || current[current.length - 1];
    const newInst = {
      ...target,
      id: `inst_${Date.now()}_${Math.random().toString(36).substr(2, 4)}`,
      targetScreen: resolveActiveScreen(target.targetScreen || curScreenId),
      x: (target.x ?? 100) + 30,
      y: (target.y ?? 100) + 30,
      sticker: target.sticker || null,
    };
    const updatedInstances = [...current, newInst];
    saveInstances(updatedInstances);
    broadcastWidgetMessage('sticker', {
      type: 'SYNC_INSTANCES',
      instances: updatedInstances,
    });
    return {
      ...previousState,
      instances: updatedInstances,
    };
  }

  if (event.type === 'REMOVE_WIDGET') {
    if (event.instanceId && event.instanceId.startsWith('blank_')) {
      const sid = resolveActiveScreen(getScreenId());
      const current = previousState.hiddenPlusScreens || [];
      if (!current.includes(sid)) {
        const updated = [...current, sid];
        saveHiddenPlusScreens(updated);
        broadcastWidgetMessage('sticker', {
          type: 'SYNC_HIDDEN_PLUS',
          hiddenPlusScreens: updated,
        });
        return {
          ...previousState,
          hiddenPlusScreens: updated,
        };
      }
      return previousState;
    }
    const current = previousState.instances || [];
    const updatedInstances = current.filter((i) => i.id !== event.instanceId);
    saveInstances(updatedInstances);
    broadcastWidgetMessage('sticker', {
      type: 'SYNC_INSTANCES',
      instances: updatedInstances,
    });
    return {
      ...previousState,
      instances: updatedInstances,
    };
  }

  if (event.type === 'ORDER_CHANGED') {
    return {
      ...previousState,
      orderTick: Date.now(),
    };
  }

  return previousState;
};

initWidgetDesktopSync({
  widgetId: 'sticker',
  helperPaths: [
    '$HOME/Library/Application Support/Übersicht/widgets/sticker.widget/menu_helper',
    './sticker.widget/menu_helper',
  ],
  getDispatch: () => currentDispatch,
  storageKeys: [STORAGE_INSTANCES_KEY, STORAGE_HIDDEN_PLUS_KEY],
  onStorageEvent: (event, dispatch) => {
    if ((event.key === STORAGE_INSTANCES_KEY || event.key === 'sticker_widget_instances') && event.newValue) {
      try {
        const parsed = JSON.parse(event.newValue);
        if (Array.isArray(parsed)) {
          dispatch({ type: 'SYNC_INSTANCES', instances: parsed });
        }
      } catch (e) {}
    } else if (event.key === STORAGE_HIDDEN_PLUS_KEY && event.newValue) {
      try {
        const parsed = JSON.parse(event.newValue);
        if (Array.isArray(parsed)) {
          dispatch({ type: 'SYNC_HIDDEN_PLUS', hiddenPlusScreens: parsed });
        }
      } catch (e) {}
    }
  },
});

export const render = (state, dispatch) => {
  const currentState = state || initialState;
  const {
    enableSnapping = true,
  } = currentState;

  currentDispatch = dispatch;
  currentWidgetState = currentState;

  ensureAnimLoopRunning();

  const currentScreenId = getScreenId();
  const preview = currentState.crossScreenPreview;
  const allInstances = (currentState && currentState.instances && currentState.instances.length > 0)
    ? currentState.instances
    : getInitialInstances();

  const screenInstances = allInstances.filter((inst) => {
    const s = inst.targetScreen || 'screen_1';
    return isScreenActive(currentScreenId, s);
  });

  const hiddenPlusScreens = currentState.hiddenPlusScreens || getHiddenPlusScreens();
  const isPlusHidden = hiddenPlusScreens.some((s) => isScreenActive(currentScreenId, s));

  if (screenInstances.length === 0 && isPlusHidden) {
    if (preview && preview.targetScreen === currentScreenId) {
      return (
        <div
          style={{
            position: 'fixed',
            top: 0,
            left: 0,
            transform: `translate3d(${Math.round(preview.x)}px, ${Math.round(preview.y)}px, 0)`,
            width: `${preview.w}px`,
            height: `${preview.h}px`,
            borderRadius: '18px',
            border: '2px dashed rgba(255, 255, 255, 0.5)',
            background: 'rgba(28, 27, 25, 0.45)',
            backdropFilter: 'blur(16px)',
            WebkitBackdropFilter: 'blur(16px)',
            boxShadow: '0 12px 32px rgba(0, 0, 0, 0.4)',
            pointerEvents: 'none',
            zIndex: 9999,
          }}
        />
      );
    }
    return <div style={{ display: 'none' }} />;
  }

  let instances = screenInstances.length > 0
    ? screenInstances
    : [{
        id: `blank_${currentScreenId}`,
        sticker: null,
        targetScreen: currentScreenId,
        x: SNAP_MARGIN_X,
        y: SNAP_MARGIN_TOP,
        scale: 1.0,
        flipped: false,
        isPaused: false,
        currentFrame: 0,
        w: BASE_SIZE,
        h: BASE_SIZE,
        audioSync: false,
        audioSensitivity: DEFAULT_AUDIO_SENSITIVITY,
      }];

  // Manage Audio Sync Polling (fast 200ms responsive loop)
  const hasAudioSync = instances.some((inst) => inst.sticker && inst.audioSync);
  if (hasAudioSync && !audioTimer) {
    audioTimer = setInterval(checkAudio, 200);
    checkAudio();
  } else if (!hasAudioSync && audioTimer) {
    clearInterval(audioTimer);
    audioTimer = null;
  }

  if (typeof localStorage !== 'undefined' && localStorage.getItem('sticker_force_blank_once') === 'true') {
    localStorage.removeItem('sticker_force_blank_once');
    const defaultPos = getInitialPosition();
    instances = [{
      id: 'default',
      sticker: null,
      targetScreen: resolveActiveScreen(currentScreenId),
      x: defaultPos.x,
      y: defaultPos.y,
      scale: 1.0,
      flipped: false,
      isPaused: false,
      currentFrame: 0,
      w: BASE_SIZE,
      h: BASE_SIZE,
    }];
    saveInstances(instances);
    if (dispatch) {
      setTimeout(() => {
        dispatch({ type: 'RESET_TO_BLANK_PLUS' });
      }, 0);
    }
  }

  const openStickerManagerHelper = (instId, currentSticker) => {
    const payload = JSON.stringify({
      mode: 'MANAGER',
      instanceId: instId,
      currentSticker: currentSticker || null,
    });
    const cmd = getHelperCmd(payload);

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
            const baseName = filename.replace(/\.[^/.]+$/, '');
            const deleteCmd = `rm -f "$HOME/Library/Application Support/Übersicht/widgets/sticker.widget/stickers/${baseName}"* "$HOME/Documents/antigravity/uebersicht-sticker/sticker.widget/stickers/${baseName}"* 2>/dev/null`;
            run(deleteCmd);
          }
          dispatch({
            type: 'CLEAR_STICKER',
            instanceId: res.instanceId || instId,
            sticker: st,
          });
        } else if (res.action === 'ADD_STICKER_INSTANCE') {
          dispatch({
            type: 'ADD_STICKER_INSTANCE',
            ...res,
          });
        }
      } catch (e) {}
    });
  };

  const openStickerStudioHelper = (instId, currentSticker) => {
    const payload = JSON.stringify({
      mode: 'STUDIO',
      instanceId: instId,
      currentSticker: currentSticker || null,
    });
    const cmd = getHelperCmd(payload);

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
        }
      } catch (e) {}
    });
  };

  const handlePlusClick = (instanceId, e) => {
    if (e && e.stopPropagation) e.stopPropagation();
    const now = Date.now();
    if (now - lastPlusClickTimestamp < 400) return;
    lastPlusClickTimestamp = now;

    const payload = JSON.stringify({
      mode: 'PLUS_CLICK',
      instanceId,
    });
    const cmd = getHelperCmd(payload);

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
            const baseName = filename.replace(/\.[^/.]+$/, '');
            const deleteCmd = `rm -f "$HOME/Library/Application Support/Übersicht/widgets/sticker.widget/stickers/${baseName}"* "$HOME/Documents/antigravity/uebersicht-sticker/sticker.widget/stickers/${baseName}"* 2>/dev/null`;
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
    if (e) {
      if (e.preventDefault) e.preventDefault();
      if (e.stopPropagation) e.stopPropagation();
    }
    const now = Date.now();
    if (now - lastContextMenuTimestamp < 350) return;
    lastContextMenuTimestamp = now;

    const payload = JSON.stringify({
      mode: 'CONTEXT_MENU',
      instanceId: instance.id,
      currentSticker: instance.sticker || null,
      scale: instance.scale || 1.0,
      flipped: Boolean(instance.flipped),
      isPaused: Boolean(instance.isPaused),
      audioSync: Boolean(instance.audioSync),
      audioSensitivity: typeof instance.audioSensitivity === 'number' ? instance.audioSensitivity : DEFAULT_AUDIO_SENSITIVITY,
      opacity: instance.opacity !== undefined ? instance.opacity : 1.0,
      shadow: instance.shadow !== false,
      enableSnapping: enableSnapping !== false,
      screenId: resolveActiveScreen(instance.targetScreen || currentScreenId),
      hiddenPlusScreens: currentState.hiddenPlusScreens || getHiddenPlusScreens(),
      x: Math.round(instance.x ?? 100),
      y: Math.round(instance.y ?? 100),
    });

    const cmd = getHelperCmd(payload);

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
            const baseName = filename.replace(/\.[^/.]+$/, '');
            const deleteCmd = `rm -f "$HOME/Library/Application Support/Übersicht/widgets/sticker.widget/stickers/${baseName}"* "$HOME/Documents/antigravity/uebersicht-sticker/sticker.widget/stickers/${baseName}"* 2>/dev/null`;
            run(deleteCmd);
          }
          dispatch({
            type: 'CLEAR_STICKER',
            instanceId: res.instanceId || instance.id,
            sticker: st,
          });
        } else if (res.action === 'OPEN_MANAGER') {
          openStickerManagerHelper(res.instanceId || instance.id, instance.sticker);
        } else if (res.action === 'OPEN_STUDIO') {
          openStickerStudioHelper(res.instanceId || instance.id, instance.sticker);
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
          dispatch({ type: 'TOGGLE_AUDIO_SYNC', instanceId: res.instanceId || instance.id });
        } else if (res.action === 'SET_AUDIO_SENSITIVITY') {
          dispatch({
            type: 'SET_AUDIO_SENSITIVITY',
            instanceId: res.instanceId || instance.id,
            audioSensitivity: res.audioSensitivity,
          });
        } else if (res.action === 'SET_OPACITY') {
          dispatch({ type: 'SET_OPACITY', instanceId: res.instanceId || instance.id, opacity: res.opacity });
        } else if (res.action === 'TOGGLE_SHADOW') {
          dispatch({ type: 'TOGGLE_SHADOW', instanceId: res.instanceId || instance.id });
        } else if (res.action === 'TOGGLE_SNAPPING') {
          dispatch({ type: 'TOGGLE_SNAPPING' });
        } else if (res.action === 'RESET_POSITION') {
          dispatch({ type: 'RESET_POSITION', instanceId: res.instanceId || instance.id });
        } else if (res.action === 'MOVE_TO_SCREEN') {
          dispatch({ type: 'MOVE_TO_SCREEN', instanceId: res.instanceId || instance.id, screenId: res.screenId });
        } else if (res.action === 'HIDE_PLUS_ON_SCREEN') {
          dispatch({ type: 'HIDE_PLUS_ON_SCREEN', screenId: res.screenId });
        } else if (res.action === 'TOGGLE_SHOW_PLUS') {
          dispatch({ type: 'TOGGLE_SHOW_PLUS', screenId: res.screenId });
        } else if (res.action === 'RELOAD_WIDGET') {
          const wid = res.widgetId || 'sticker-widget-index-jsx';
          run(`osascript -e 'tell application id "tracesOf.Uebersicht" to reload widget id "${wid}"' 2>/dev/null || osascript -e 'tell application id "tracesOf.Uebersicht" to refresh'`);
        } else if (res.action === 'REMOVE_WIDGET') {
          dispatch({ type: 'REMOVE_WIDGET', instanceId: res.instanceId || instance.id, widgetId: res.widgetId || 'sticker-widget-index-jsx' });
        } else if (res.action === 'DUPLICATE_WIDGET') {
          dispatch({ type: 'DUPLICATE_WIDGET', instanceId: res.instanceId || instance.id });
        } else if (res.action === 'ORDER_FRONT' || res.action === 'ORDER_FORWARD' || res.action === 'ORDER_BACKWARD' || res.action === 'ORDER_BACK') {
          dispatch({ type: res.action, instanceId: res.instanceId || instance.id });
        }
      } catch (parseErr) {}
    });
  };

  if (typeof window !== 'undefined') {
    requestAnimationFrame(() => {
      instances.forEach((inst) => {
        if (inst.sticker) {
          const cur = animFrameState[inst.id]?.currentFrame ?? inst.currentFrame ?? 0;
          drawCanvasFrame(inst.id, inst.sticker, cur);
        }
      });
    });
  }

  return (
    <div className="sticker-root">
      {preview && preview.targetScreen === currentScreenId && (
        <div
          style={{
            position: 'fixed',
            top: 0,
            left: 0,
            transform: `translate3d(${Math.round(preview.x)}px, ${Math.round(preview.y)}px, 0)`,
            width: `${preview.w}px`,
            height: `${preview.h}px`,
            borderRadius: '18px',
            border: '2px dashed rgba(255, 255, 255, 0.5)',
            background: 'rgba(28, 27, 25, 0.45)',
            backdropFilter: 'blur(16px)',
            WebkitBackdropFilter: 'blur(16px)',
            boxShadow: '0 12px 32px rgba(0, 0, 0, 0.4)',
            pointerEvents: 'none',
            zIndex: 9999,
          }}
        />
      )}
      {instances.map((instance, index) => {
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
              setTimeout(() => {
                dispatch({
                  type: 'SET_NATURAL_SIZE',
                  instanceId: instance.id,
                  w: fitW,
                  h: fitH,
                });
              }, 0);
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
          setTimeout(() => {
            dispatch({
              type: 'SET_NATURAL_SIZE',
              instanceId: instance.id,
              w: fitW,
              h: fitH,
            });
          }, 0);
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
          if (e.button !== 0) return;

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
          let rafPending = false;
          let lastBroadcastOverhang = false;

          const handleMouseMove = (moveEvent) => {
            const dx = moveEvent.clientX - startX;
            const dy = moveEvent.clientY - startY;

            if (!hasMoved) {
              if (Math.hypot(dx, dy) > 8) {
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
              const clientX = moveEvent.clientX;
              const clientY = moveEvent.clientY;
              const bypassSnap = moveEvent.metaKey || moveEvent.altKey || moveEvent.shiftKey;

              if (!rafPending) {
                rafPending = true;
                requestAnimationFrame(() => {
                  rafPending = false;
                  dispatch({
                    type: 'MOVE_DRAG',
                    clientX,
                    clientY,
                    bypassSnap,
                  });

                  const rawX = x + (clientX - startX);
                  const rawY = y + (clientY - startY);
                  const crossPreview = computeCrossScreenPreview(currentScreenId, rawX, rawY, instCardW, instCardH);
                  if (crossPreview || lastBroadcastOverhang) {
                    lastBroadcastOverhang = Boolean(crossPreview);
                    broadcastWidgetMessage('sticker', {
                      type: 'CROSS_SCREEN_DRAG_PREVIEW',
                      preview: crossPreview,
                    });
                  }
                });
              }
            }
          };

          const handleMouseUp = (upEvent) => {
            window.removeEventListener('mousemove', handleMouseMove);
            window.removeEventListener('mouseup', handleMouseUp);
            if (hasMoved) {
              dispatch({ type: 'END_DRAG' });
            } else if (!hasSticker) {
              handlePlusClick(instance.id, upEvent || e);
            }
          };

          window.addEventListener('mousemove', handleMouseMove);
          window.addEventListener('mouseup', handleMouseUp);
        };

        const containerStyle = {
          position: 'fixed',
          top: 0,
          left: 0,
          transform: `translate3d(${Math.round(x)}px, ${Math.round(y)}px, 0)`,
          willChange: isDragging ? 'transform' : 'auto',
          width: `${instCardW}px`,
          height: `${instCardH}px`,
          boxSizing: 'border-box',
          zIndex: isDragging ? 9999 : (getWidgetZIndex('sticker') + index),
          pointerEvents: 'auto',
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

        const instOpacity = instance.opacity !== undefined ? instance.opacity : 1.0;
        const stickerStyle = {
          position: 'relative',
          width: '100%',
          height: '100%',
          pointerEvents: 'auto',
          cursor: isDragging ? 'grabbing' : 'grab',
          transform: instFlipped ? 'scaleX(-1)' : 'none',
          opacity: instOpacity,
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
              <div
                className="sticker-blank-square"
                style={blankSquareStyle}
                onMouseDown={handleMouseDown}
                onClick={(clickEvent) => {
                  if (!hasSticker) {
                    handlePlusClick(instance.id, clickEvent);
                  }
                }}
                title="Click to select Sticker (GIF, WebP, PNG) (or drag to position, right-click for options)"
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
