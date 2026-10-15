import { React, run } from 'uebersicht';

export const refreshFrequency = false;
export const command = '';

const BASE_WIDTH = 215;
const BASE_HEIGHT = 146;
const TOTAL_FRAMES = 186;
const COLS = 14;
const FRAME_DURATION = 70; // 70ms per frame (~14.3 fps)

const STORAGE_POS_KEY = 'sticker_widget_position';
const STORAGE_SCALE_KEY = 'sticker_widget_scale';
const STORAGE_FLIP_KEY = 'sticker_widget_flipped';
const STORAGE_PAUSE_KEY = 'sticker_widget_paused';
const STORAGE_FRAME_KEY = 'sticker_widget_frame_index';
const STORAGE_AUDIO_SYNC_KEY = 'sticker_widget_audio_sync';
const STORAGE_OPACITY_KEY = 'sticker_widget_opacity';
const STORAGE_SHADOW_KEY = 'sticker_widget_shadow';
const STORAGE_SNAP_KEY = 'sticker_widget_snapping';

const SCREEN_MARGIN = 0;
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
let currentAnimFrame = 0;
let sheetImage = null;
let sheetLoaded = false;
let animRafId = null;
let lastFrameTimestamp = 0;

const drawFrame = (frameIndex) => {
  const canvas = document.getElementById('sticker-canvas');
  if (!canvas || !sheetLoaded || !sheetImage) return;
  const ctx = canvas.getContext('2d');
  if (!ctx) return;

  const validIndex = Math.max(0, Math.min(TOTAL_FRAMES - 1, frameIndex));
  const col = validIndex % COLS;
  const row = Math.floor(validIndex / COLS);

  ctx.clearRect(0, 0, BASE_WIDTH, BASE_HEIGHT);
  ctx.drawImage(
    sheetImage,
    col * BASE_WIDTH,
    row * BASE_HEIGHT,
    BASE_WIDTH,
    BASE_HEIGHT,
    0,
    0,
    BASE_WIDTH,
    BASE_HEIGHT
  );
};

const animLoop = (now) => {
  if (!currentWidgetState || currentWidgetState.isPaused) {
    animRafId = null;
    return;
  }

  if (!lastFrameTimestamp) lastFrameTimestamp = now;
  const delta = now - lastFrameTimestamp;

  if (delta >= FRAME_DURATION) {
    const steps = Math.floor(delta / FRAME_DURATION);
    currentAnimFrame = (currentAnimFrame + steps) % TOTAL_FRAMES;
    lastFrameTimestamp = now - (delta % FRAME_DURATION);
    drawFrame(currentAnimFrame);
  }

  animRafId = requestAnimationFrame(animLoop);
};

const startAnimation = () => {
  if (animRafId !== null) return;
  lastFrameTimestamp = performance.now();
  animRafId = requestAnimationFrame(animLoop);
};

const stopAnimation = () => {
  if (animRafId !== null) {
    cancelAnimationFrame(animRafId);
    animRafId = null;
  }
};

const initSheetImage = () => {
  if (typeof Image === 'undefined' || sheetImage) return;
  sheetImage = new Image();
  sheetImage.src = 'sticker.widget/spiderman_sheet.webp';
  sheetImage.onload = () => {
    sheetLoaded = true;
    drawFrame(currentAnimFrame);
    if (currentWidgetState && !currentWidgetState.isPaused) {
      startAnimation();
    }
  };
};

initSheetImage();

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

    if (isPlaying && state.isPaused) {
      currentDispatch({ type: 'AUDIO_STATUS_CHANGED', isPlaying: true });
    } else if (!isPlaying && !state.isPaused) {
      currentDispatch({ type: 'AUDIO_STATUS_CHANGED', isPlaying: false });
    }
  });
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

    // Horizontal snapping: release when moving closer to screen edge than guideline
    if (newX >= snapLeft - SNAP_EDGE_TOLERANCE && newX <= snapLeft + SNAP_THRESHOLD) {
      newX = snapLeft;
    } else if (newX >= snapRight - SNAP_THRESHOLD && newX <= snapRight + SNAP_EDGE_TOLERANCE) {
      newX = snapRight;
    }

    // Vertical snapping: release when moving closer to top/bottom edge than guideline
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

  try {
    const saved = typeof localStorage !== 'undefined' ? localStorage.getItem(STORAGE_POS_KEY) : null;
    if (saved) {
      const parsed = JSON.parse(saved);
      if (typeof parsed.x === 'number' && typeof parsed.y === 'number') {
        const maxX = Math.max(0, winW - cardW);
        const maxY = Math.max(0, winH - cardH);
        return {
          x: Math.max(0, Math.min(maxX, parsed.x)),
          y: Math.max(0, Math.min(maxY, parsed.y)),
        };
      }
    }
  } catch (e) {}

  // Default to bottom-right resting above dock
  return {
    x: Math.max(SNAP_MARGIN_X, winW - cardW - SNAP_MARGIN_X),
    y: Math.max(SNAP_MARGIN_TOP, winH - cardH - SNAP_MARGIN_BOTTOM),
  };
};

const getInitialScale = () => {
  try {
    const saved = typeof localStorage !== 'undefined' ? localStorage.getItem(STORAGE_SCALE_KEY) : null;
    if (saved) {
      const val = parseFloat(saved);
      if (!isNaN(val) && val >= 0.25 && val <= 3.0) return val;
    }
  } catch (e) {}
  return 1.0;
};

const getInitialFlipped = () => {
  try {
    const saved = typeof localStorage !== 'undefined' ? localStorage.getItem(STORAGE_FLIP_KEY) : null;
    if (saved !== null) return saved === 'true';
  } catch (e) {}
  return false;
};

const getInitialPaused = () => {
  try {
    const saved = typeof localStorage !== 'undefined' ? localStorage.getItem(STORAGE_PAUSE_KEY) : null;
    if (saved !== null) return saved === 'true';
  } catch (e) {}
  return false;
};

const getInitialFrameIndex = () => {
  try {
    const saved = typeof localStorage !== 'undefined' ? localStorage.getItem(STORAGE_FRAME_KEY) : null;
    if (saved) {
      const val = parseInt(saved, 10);
      if (!isNaN(val) && val >= 0 && val < TOTAL_FRAMES) return val;
    }
  } catch (e) {}
  return 0;
};

const getInitialAudioSync = () => {
  try {
    const saved = typeof localStorage !== 'undefined' ? localStorage.getItem(STORAGE_AUDIO_SYNC_KEY) : null;
    if (saved !== null) return saved === 'true';
  } catch (e) {}
  return false;
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
  try {
    const saved = typeof localStorage !== 'undefined' ? localStorage.getItem(STORAGE_SNAP_KEY) : null;
    if (saved !== null) return saved === 'true';
  } catch (e) {}
  return true;
};

const initialScale = getInitialScale();
const initialCardW = Math.round(BASE_WIDTH * initialScale);
const initialCardH = Math.round(BASE_HEIGHT * initialScale);
const initialPos = getInitialPosition(initialCardW, initialCardH);
currentAnimFrame = getInitialFrameIndex();

export const initialState = {
  x: initialPos.x,
  y: initialPos.y,
  scale: initialScale,
  cardWidth: initialCardW,
  cardHeight: initialCardH,
  flipped: getInitialFlipped(),
  isPaused: getInitialPaused(),
  audioSync: getInitialAudioSync(),
  opacity: getInitialOpacity(),
  shadow: getInitialShadow(),
  enableSnapping: getInitialSnapping(),
  isDragging: false,
  dragStartX: 0,
  dragStartY: 0,
  startPosX: 0,
  startPosY: 0,
};

export const updateState = (event, previousState) => {
  if (!previousState) return initialState;

  if (event.type === 'START_DRAG') {
    return {
      ...previousState,
      isDragging: true,
      dragStartX: event.clientX,
      dragStartY: event.clientY,
      startPosX: previousState.x,
      startPosY: previousState.y,
    };
  }

  if (event.type === 'MOVE_DRAG' && previousState.isDragging) {
    const deltaX = event.clientX - previousState.dragStartX;
    const deltaY = event.clientY - previousState.dragStartY;
    const bypassSnap = !previousState.enableSnapping || event.bypassSnap;

    const { x: newX, y: newY } = calculateSnappedPosition(
      previousState.startPosX + deltaX,
      previousState.startPosY + deltaY,
      previousState.cardWidth,
      previousState.cardHeight,
      bypassSnap,
      previousState.enableSnapping
    );

    try {
      localStorage.setItem(STORAGE_POS_KEY, JSON.stringify({ x: newX, y: newY }));
    } catch (e) {}

    return {
      ...previousState,
      x: newX,
      y: newY,
    };
  }

  if (event.type === 'END_DRAG') {
    return {
      ...previousState,
      isDragging: false,
    };
  }

  if (event.type === 'SET_SCALE') {
    const nextScale = event.scale;
    const newW = Math.round(BASE_WIDTH * nextScale);
    const newH = Math.round(BASE_HEIGHT * nextScale);
    const winW = typeof window !== 'undefined' ? (window.innerWidth || 1920) : 1920;
    const winH = typeof window !== 'undefined' ? (window.innerHeight || 1080) : 1080;
    const maxX = Math.max(0, winW - newW);
    const maxY = Math.max(0, winH - newH);

    const clampedX = Math.max(0, Math.min(maxX, previousState.x));
    const clampedY = Math.max(0, Math.min(maxY, previousState.y));

    try {
      localStorage.setItem(STORAGE_SCALE_KEY, String(nextScale));
      localStorage.setItem(STORAGE_POS_KEY, JSON.stringify({ x: clampedX, y: clampedY }));
    } catch (e) {}

    return {
      ...previousState,
      scale: nextScale,
      cardWidth: newW,
      cardHeight: newH,
      x: clampedX,
      y: clampedY,
    };
  }

  if (event.type === 'TOGGLE_FLIP') {
    const nextFlipped = !previousState.flipped;
    try {
      localStorage.setItem(STORAGE_FLIP_KEY, String(nextFlipped));
    } catch (e) {}
    return {
      ...previousState,
      flipped: nextFlipped,
    };
  }

  if (event.type === 'SET_FLIP') {
    try {
      localStorage.setItem(STORAGE_FLIP_KEY, String(event.flipped));
    } catch (e) {}
    return {
      ...previousState,
      flipped: event.flipped,
    };
  }

  if (event.type === 'TOGGLE_PAUSE') {
    const nextPaused = !previousState.isPaused;
    try {
      localStorage.setItem(STORAGE_PAUSE_KEY, String(nextPaused));
      localStorage.setItem(STORAGE_FRAME_KEY, String(currentAnimFrame));
    } catch (e) {}
    return {
      ...previousState,
      isPaused: nextPaused,
    };
  }

  if (event.type === 'TOGGLE_AUDIO_SYNC') {
    const nextSync = !previousState.audioSync;
    try {
      localStorage.setItem(STORAGE_AUDIO_SYNC_KEY, String(nextSync));
    } catch (e) {}
    return {
      ...previousState,
      audioSync: nextSync,
    };
  }

  if (event.type === 'AUDIO_STATUS_CHANGED') {
    const isPlaying = event.isPlaying;
    if (isPlaying && previousState.isPaused) {
      try {
        localStorage.setItem(STORAGE_PAUSE_KEY, 'false');
      } catch (e) {}
      return {
        ...previousState,
        isPaused: false,
      };
    } else if (!isPlaying && !previousState.isPaused) {
      try {
        localStorage.setItem(STORAGE_PAUSE_KEY, 'true');
        localStorage.setItem(STORAGE_FRAME_KEY, String(currentAnimFrame));
      } catch (e) {}
      return {
        ...previousState,
        isPaused: true,
      };
    }
    return previousState;
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
    try {
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
    const defaultX = Math.max(SNAP_MARGIN_X, winW - previousState.cardWidth - SNAP_MARGIN_X);
    const defaultY = Math.max(SNAP_MARGIN_TOP, winH - previousState.cardHeight - SNAP_MARGIN_BOTTOM);
    try {
      localStorage.setItem(STORAGE_POS_KEY, JSON.stringify({ x: defaultX, y: defaultY }));
    } catch (e) {}
    return {
      ...previousState,
      x: defaultX,
      y: defaultY,
    };
  }

  return previousState;
};

export const render = (state, dispatch) => {
  const currentState = state && typeof state.x === 'number' ? state : initialState;
  const {
    x,
    y,
    scale,
    cardWidth,
    cardHeight,
    flipped,
    isPaused,
    audioSync,
    opacity,
    shadow,
    enableSnapping,
    isDragging,
  } = currentState;

  currentDispatch = dispatch;
  currentWidgetState = currentState;

  // Manage Animation Playback State
  if (!isPaused) {
    startAnimation();
  } else {
    stopAnimation();
    drawFrame(currentAnimFrame);
  }

  // Manage Audio Sync Polling (fast 200ms responsive loop)
  if (audioSync && !audioTimer) {
    audioTimer = setInterval(checkAudio, 200);
    checkAudio();
  } else if (!audioSync && audioTimer) {
    clearInterval(audioTimer);
    audioTimer = null;
  }

  const handleMouseDown = (e) => {
    if (e.button !== 0) return; // Only primary button

    const now = Date.now();
    const isDoubleClick = now - lastClickTimestamp < 320;
    lastClickTimestamp = now;

    if (isDoubleClick) {
      e.preventDefault();
      dispatch({ type: 'TOGGLE_FLIP' });
      return;
    }

    const startX = e.clientX;
    const startY = e.clientY;
    let hasMoved = false;

    const handleMouseMove = (moveEvent) => {
      const dx = moveEvent.clientX - startX;
      const dy = moveEvent.clientY - startY;

      if (!hasMoved) {
        if (Math.hypot(dx, dy) > 3) {
          hasMoved = true;
          dispatch({
            type: 'START_DRAG',
            clientX: startX,
            clientY: startY,
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
      }
    };

    window.addEventListener('mousemove', handleMouseMove);
    window.addEventListener('mouseup', handleMouseUp);
  };

  const handleDoubleClick = (e) => {
    e.preventDefault();
    e.stopPropagation();
    dispatch({ type: 'TOGGLE_FLIP' });
  };

  const handleContextMenu = (e) => {
    e.preventDefault();
    e.stopPropagation();

    const payload = JSON.stringify({
      scale: scale || 1.0,
      flipped: Boolean(flipped),
      isPaused: Boolean(isPaused),
      audioSync: Boolean(audioSync),
      opacity: opacity !== undefined ? opacity : 1.0,
      shadow: shadow !== false,
      snapping: enableSnapping !== false,
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

        if (res.action === 'SET_SCALE') {
          dispatch({ type: 'SET_SCALE', scale: res.scale });
        } else if (res.action === 'SET_FLIP') {
          dispatch({ type: 'SET_FLIP', flipped: res.flipped });
        } else if (res.action === 'TOGGLE_PAUSE') {
          dispatch({ type: 'TOGGLE_PAUSE' });
        } else if (res.action === 'TOGGLE_AUDIO_SYNC') {
          dispatch({ type: 'TOGGLE_AUDIO_SYNC' });
        } else if (res.action === 'SET_OPACITY') {
          dispatch({ type: 'SET_OPACITY', opacity: res.opacity });
        } else if (res.action === 'TOGGLE_SHADOW') {
          dispatch({ type: 'TOGGLE_SHADOW' });
        } else if (res.action === 'TOGGLE_SNAPPING') {
          dispatch({ type: 'TOGGLE_SNAPPING' });
        } else if (res.action === 'RESET_POSITION') {
          dispatch({ type: 'RESET_POSITION' });
        }
      } catch (parseErr) {}
    });
  };

  const SHADOW_PAD = 24;

  const containerStyle = {
    position: 'absolute',
    top: `${y - SHADOW_PAD}px`,
    left: `${x - SHADOW_PAD}px`,
    width: `${cardWidth + SHADOW_PAD * 2}px`,
    height: `${cardHeight + SHADOW_PAD * 2}px`,
    padding: `${SHADOW_PAD}px`,
    boxSizing: 'border-box',
    zIndex: 100,
    pointerEvents: 'none',
    userSelect: 'none',
    WebkitUserSelect: 'none',
  };

  const stickerStyle = {
    width: '100%',
    height: '100%',
    pointerEvents: 'auto',
    cursor: isDragging ? 'grabbing' : 'grab',
    transform: flipped ? 'scaleX(-1)' : 'none',
    opacity: opacity,
    filter: (shadow && !isDragging) ? 'drop-shadow(0 4px 12px rgba(0, 0, 0, 0.35))' : 'none',
    transition: isDragging ? 'none' : 'opacity 0.2s ease, filter 0.15s ease, transform 0.2s cubic-bezier(0.34, 1.56, 0.64, 1)',
  };

  return (
    <div className="sticker-root">
      {/* Padded Container to prevent shadow cutoff */}
      <div
        id="sticker-container"
        style={containerStyle}
      >
        {/* Interactive Sticker Box */}
        <div
          id="sticker-interactive"
          style={stickerStyle}
          onMouseDown={handleMouseDown}
          onDoubleClick={handleDoubleClick}
          onContextMenu={handleContextMenu}
          title="Spider-Man Sticker (Drag to move, Double-click to flip, Right-click for options)"
        >
          <canvas
            id="sticker-canvas"
            width={BASE_WIDTH}
            height={BASE_HEIGHT}
            style={{
              width: '100%',
              height: '100%',
              objectFit: 'contain',
              pointerEvents: 'none',
              userSelect: 'none',
              WebkitUserSelect: 'none',
              imageRendering: '-webkit-optimize-contrast',
            }}
          />
        </div>
      </div>
    </div>
  );
};

export const className = `
  font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro Display", "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
  color: #ffffff;
`;
