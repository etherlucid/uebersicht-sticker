import { React } from 'uebersicht';

export const refreshFrequency = false;
export const command = '';

const BASE_WIDTH = 262;
const BASE_HEIGHT = 200;

const STORAGE_POS_KEY = 'sticker_widget_position';
const STORAGE_SCALE_KEY = 'sticker_widget_scale';
const STORAGE_FLIP_KEY = 'sticker_widget_flipped';
const STORAGE_PAUSE_KEY = 'sticker_widget_paused';
const STORAGE_PAUSE_FRAME_KEY = 'sticker_widget_paused_frame';
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

const getInitialPausedFrame = () => {
  try {
    return typeof localStorage !== 'undefined' ? localStorage.getItem(STORAGE_PAUSE_FRAME_KEY) : null;
  } catch (e) {}
  return null;
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

export const initialState = {
  x: initialPos.x,
  y: initialPos.y,
  scale: initialScale,
  cardWidth: initialCardW,
  cardHeight: initialCardH,
  flipped: getInitialFlipped(),
  isPaused: getInitialPaused(),
  pausedFrame: getInitialPausedFrame(),
  opacity: getInitialOpacity(),
  shadow: getInitialShadow(),
  enableSnapping: getInitialSnapping(),
  contextMenu: null,
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
      contextMenu: null,
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
      if (nextPaused && event.pausedFrame) {
        localStorage.setItem(STORAGE_PAUSE_FRAME_KEY, event.pausedFrame);
      } else {
        localStorage.removeItem(STORAGE_PAUSE_FRAME_KEY);
      }
    } catch (e) {}
    return {
      ...previousState,
      isPaused: nextPaused,
      pausedFrame: event.pausedFrame !== undefined ? event.pausedFrame : (nextPaused ? previousState.pausedFrame : null),
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
      contextMenu: null,
    };
  }

  if (event.type === 'OPEN_CONTEXT_MENU') {
    return {
      ...previousState,
      contextMenu: { x: event.x, y: event.y },
    };
  }

  if (event.type === 'CLOSE_CONTEXT_MENU') {
    return {
      ...previousState,
      contextMenu: null,
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
    pausedFrame,
    opacity,
    shadow,
    enableSnapping,
    contextMenu,
    isDragging,
  } = currentState;

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
    const menuW = 195;
    const menuH = 340;
    const winW = typeof window !== 'undefined' ? (window.innerWidth || 1920) : 1920;
    const winH = typeof window !== 'undefined' ? (window.innerHeight || 1080) : 1080;
    const maxX = winW - menuW - 12;
    const maxY = winH - menuH - 12;
    dispatch({
      type: 'OPEN_CONTEXT_MENU',
      x: Math.max(12, Math.min(maxX, e.clientX)),
      y: Math.max(12, Math.min(maxY, e.clientY)),
    });
  };

  const handleTogglePause = () => {
    if (!isPaused) {
      let frameData = null;
      try {
        const img = document.getElementById('sticker-spiderman-img');
        if (img) {
          const canvas = document.createElement('canvas');
          canvas.width = img.naturalWidth || BASE_WIDTH;
          canvas.height = img.naturalHeight || BASE_HEIGHT;
          const ctx = canvas.getContext('2d');
          ctx.drawImage(img, 0, 0);
          frameData = canvas.toDataURL('image/png');
        }
      } catch (err) {
        console.warn('Sticker freeze frame capture note:', err);
      }
      dispatch({ type: 'TOGGLE_PAUSE', pausedFrame: frameData });
    } else {
      dispatch({ type: 'TOGGLE_PAUSE', pausedFrame: null });
    }
  };

  const containerStyle = {
    position: 'absolute',
    top: `${y}px`,
    left: `${x}px`,
    width: `${cardWidth}px`,
    height: `${cardHeight}px`,
    zIndex: 100,
    cursor: isDragging ? 'grabbing' : 'grab',
    userSelect: 'none',
    WebkitUserSelect: 'none',
    transform: flipped ? 'scaleX(-1)' : 'none',
    opacity: opacity,
    filter: shadow ? 'drop-shadow(0 10px 22px rgba(0, 0, 0, 0.45))' : 'none',
    transition: isDragging ? 'none' : 'opacity 0.2s ease, filter 0.2s ease, transform 0.2s cubic-bezier(0.34, 1.56, 0.64, 1)',
  };

  const SCALE_OPTIONS = [
    { label: '50%', value: 0.5 },
    { label: '75%', value: 0.75 },
    { label: '100%', value: 1.0 },
    { label: '125%', value: 1.25 },
    { label: '150%', value: 1.5 },
  ];

  const OPACITY_OPTIONS = [
    { label: '100%', value: 1.0 },
    { label: '80%', value: 0.8 },
    { label: '60%', value: 0.6 },
    { label: '40%', value: 0.4 },
  ];

  return (
    <div className="sticker-root">
      {/* Draggable Sticker Container */}
      <div
        id="sticker-container"
        style={containerStyle}
        onMouseDown={handleMouseDown}
        onDoubleClick={handleDoubleClick}
        onContextMenu={handleContextMenu}
        title="Spider-Man Sticker (Drag to move, Double-click to flip, Right-click for options)"
      >
        <img
          id="sticker-spiderman-img"
          src={isPaused && pausedFrame ? pausedFrame : 'sticker.widget/spiderman.webp'}
          alt="Spider-Man Sticker"
          draggable={false}
          onDragStart={(e) => e.preventDefault()}
          style={{
            width: '100%',
            height: '100%',
            objectFit: 'contain',
            pointerEvents: 'none',
            userSelect: 'none',
            WebkitUserSelect: 'none',
            WebkitUserDrag: 'none',
          }}
        />
      </div>

      {/* Context Menu Modal & Backdrop */}
      {contextMenu && (
        <>
          <div
            style={{
              position: 'fixed',
              top: 0,
              left: 0,
              width: '100vw',
              height: '100vh',
              zIndex: 9998,
              background: 'transparent',
            }}
            onClick={(e) => {
              e.stopPropagation();
              dispatch({ type: 'CLOSE_CONTEXT_MENU' });
            }}
            onContextMenu={(e) => {
              e.preventDefault();
              e.stopPropagation();
              dispatch({ type: 'CLOSE_CONTEXT_MENU' });
            }}
          />

          <div
            className="sticker-ctx-menu"
            style={{
              position: 'fixed',
              top: `${contextMenu.y}px`,
              left: `${contextMenu.x}px`,
              zIndex: 9999,
              backgroundColor: 'rgba(24, 24, 28, 0.94)',
              backdropFilter: 'blur(30px) saturate(200%)',
              WebkitBackdropFilter: 'blur(30px) saturate(200%)',
              border: '1px solid rgba(255, 255, 255, 0.14)',
              borderRadius: '13px',
              padding: '6px',
              boxShadow: '0 14px 38px rgba(0, 0, 0, 0.7), 0 2px 8px rgba(0, 0, 0, 0.4)',
              width: '185px',
              color: '#ffffff',
              userSelect: 'none',
              WebkitUserSelect: 'none',
            }}
            onClick={(e) => e.stopPropagation()}
            onContextMenu={(e) => e.preventDefault()}
          >
            {/* Header */}
            <div
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: '6px',
                padding: '4px 8px 6px 8px',
                borderBottom: '1px solid rgba(255, 255, 255, 0.08)',
                marginBottom: '5px',
              }}
            >
              <span style={{ fontSize: '12px' }}>🕷️</span>
              <span
                style={{
                  fontSize: '10px',
                  fontWeight: '700',
                  color: 'rgba(255, 255, 255, 0.75)',
                  textTransform: 'uppercase',
                  letterSpacing: '0.6px',
                }}
              >
                Spider-Man Sticker
              </span>
            </div>

            {/* Size Section */}
            <div style={sectionHeaderStyle}>Size</div>
            <div style={pillRowStyle}>
              {SCALE_OPTIONS.map((opt) => {
                const isSelected = Math.abs(scale - opt.value) < 0.01;
                return (
                  <button
                    key={opt.value}
                    type="button"
                    className="sticker-pill-btn"
                    onClick={(e) => {
                      e.stopPropagation();
                      dispatch({ type: 'SET_SCALE', scale: opt.value });
                    }}
                    style={{
                      ...pillBtnStyle,
                      backgroundColor: isSelected ? 'rgba(255, 255, 255, 0.22)' : 'rgba(255, 255, 255, 0.06)',
                      fontWeight: isSelected ? '600' : '400',
                      color: isSelected ? '#FFFFFF' : 'rgba(255, 255, 255, 0.75)',
                    }}
                  >
                    {opt.label}
                  </button>
                );
              })}
            </div>

            {/* Direction Section */}
            <div style={{ ...sectionHeaderStyle, marginTop: '5px' }}>Facing</div>
            <div style={pillRowStyle}>
              <button
                type="button"
                className="sticker-pill-btn"
                onClick={(e) => {
                  e.stopPropagation();
                  dispatch({ type: 'SET_FLIP', flipped: true });
                }}
                style={{
                  ...pillBtnStyle,
                  flex: 1,
                  backgroundColor: flipped ? 'rgba(255, 255, 255, 0.22)' : 'rgba(255, 255, 255, 0.06)',
                  fontWeight: flipped ? '600' : '400',
                  color: flipped ? '#FFFFFF' : 'rgba(255, 255, 255, 0.75)',
                }}
              >
                ◀ Left
              </button>
              <button
                type="button"
                className="sticker-pill-btn"
                onClick={(e) => {
                  e.stopPropagation();
                  dispatch({ type: 'SET_FLIP', flipped: false });
                }}
                style={{
                  ...pillBtnStyle,
                  flex: 1,
                  backgroundColor: !flipped ? 'rgba(255, 255, 255, 0.22)' : 'rgba(255, 255, 255, 0.06)',
                  fontWeight: !flipped ? '600' : '400',
                  color: !flipped ? '#FFFFFF' : 'rgba(255, 255, 255, 0.75)',
                }}
              >
                Right ▶
              </button>
            </div>

            {/* Animation Toggle */}
            <div
              className="sticker-ctx-item"
              onClick={(e) => {
                e.stopPropagation();
                handleTogglePause();
              }}
              style={{
                ...menuItemStyle,
                marginTop: '6px',
                backgroundColor: isPaused ? 'rgba(255, 179, 0, 0.15)' : 'transparent',
              }}
            >
              <span style={{ display: 'flex', alignItems: 'center', gap: '7px' }}>
                <span style={{ fontSize: '11px' }}>{isPaused ? '▶' : '⏸'}</span>
                <span>{isPaused ? 'Resume Animation' : 'Pause Animation'}</span>
              </span>
              <span style={{ fontSize: '10px', color: 'rgba(255, 255, 255, 0.5)' }}>
                {isPaused ? 'Paused' : 'Playing'}
              </span>
            </div>

            {/* Opacity Section */}
            <div style={{ ...sectionHeaderStyle, marginTop: '6px' }}>Opacity</div>
            <div style={pillRowStyle}>
              {OPACITY_OPTIONS.map((opt) => {
                const isSelected = Math.abs(opacity - opt.value) < 0.01;
                return (
                  <button
                    key={opt.value}
                    type="button"
                    className="sticker-pill-btn"
                    onClick={(e) => {
                      e.stopPropagation();
                      dispatch({ type: 'SET_OPACITY', opacity: opt.value });
                    }}
                    style={{
                      ...pillBtnStyle,
                      backgroundColor: isSelected ? 'rgba(255, 255, 255, 0.22)' : 'rgba(255, 255, 255, 0.06)',
                      fontWeight: isSelected ? '600' : '400',
                      color: isSelected ? '#FFFFFF' : 'rgba(255, 255, 255, 0.75)',
                    }}
                  >
                    {opt.label}
                  </button>
                );
              })}
            </div>

            {/* Toggles Divider */}
            <div style={{ height: '1px', background: 'rgba(255, 255, 255, 0.08)', margin: '6px 0 4px 0' }} />

            {/* Drop Shadow Toggle */}
            <div
              className="sticker-ctx-item"
              onClick={(e) => {
                e.stopPropagation();
                dispatch({ type: 'TOGGLE_SHADOW' });
              }}
              style={menuItemStyle}
            >
              <span>Ambient Shadow</span>
              {shadow && <CheckmarkIcon />}
            </div>

            {/* Edge Snapping Toggle */}
            <div
              className="sticker-ctx-item"
              onClick={(e) => {
                e.stopPropagation();
                dispatch({ type: 'TOGGLE_SNAPPING' });
              }}
              style={menuItemStyle}
            >
              <span>Edge Snapping</span>
              {enableSnapping && <CheckmarkIcon />}
            </div>

            {/* Reset Action */}
            <div
              className="sticker-ctx-item sticker-ctx-action"
              onClick={(e) => {
                e.stopPropagation();
                dispatch({ type: 'RESET_POSITION' });
              }}
              style={{
                ...menuItemStyle,
                marginTop: '4px',
                borderTop: '1px solid rgba(255, 255, 255, 0.08)',
                color: 'rgba(255, 255, 255, 0.7)',
              }}
            >
              <span>Reset Position</span>
              <span style={{ fontSize: '11px', opacity: 0.6 }}>↺</span>
            </div>
          </div>
        </>
      )}
    </div>
  );
};

const CheckmarkIcon = () => (
  <svg
    width="12"
    height="12"
    viewBox="0 0 24 24"
    fill="none"
    stroke="#FFFFFF"
    strokeWidth="2.5"
    strokeLinecap="round"
    strokeLinejoin="round"
  >
    <polyline points="20 6 9 17 4 12" />
  </svg>
);

const sectionHeaderStyle = {
  fontSize: '9px',
  fontWeight: '700',
  color: 'rgba(255, 255, 255, 0.45)',
  textTransform: 'uppercase',
  letterSpacing: '0.6px',
  padding: '2px 4px 3px 4px',
};

const pillRowStyle = {
  display: 'flex',
  gap: '3px',
  marginBottom: '2px',
};

const pillBtnStyle = {
  flex: 1,
  padding: '4px 0',
  border: 'none',
  borderRadius: '6px',
  fontSize: '10.5px',
  cursor: 'pointer',
  outline: 'none',
  textAlign: 'center',
  transition: 'background-color 0.12s ease, transform 0.08s ease',
};

const menuItemStyle = {
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'space-between',
  padding: '5px 8px',
  borderRadius: '7px',
  fontSize: '11.5px',
  color: 'rgba(255, 255, 255, 0.88)',
  cursor: 'pointer',
  margin: '1px 0',
};

export const className = `
  font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro Display", "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
  color: #ffffff;

  .sticker-pill-btn:hover {
    background-color: rgba(255, 255, 255, 0.3) !important;
    color: #ffffff !important;
  }
  .sticker-pill-btn:active {
    transform: scale(0.95);
  }

  .sticker-ctx-item {
    transition: background-color 0.1s ease, color 0.1s ease;
  }
  .sticker-ctx-item:hover {
    background-color: rgba(255, 255, 255, 0.18) !important;
    color: #ffffff !important;
  }
  .sticker-ctx-item:active {
    background-color: rgba(255, 255, 255, 0.25) !important;
  }

  .sticker-ctx-action:hover {
    color: #ffb7b7 !important;
  }
`;
