{-# LANGUAGE RecordWildCards #-}

module Monomer.Widgets.Util.Style (
  StyleChangeCfg(..),
  GetBaseStyle(..),
  activeTheme,
  activeTheme_,
  activeStyle,
  activeStyle_,
  focusedStyle,
  initInstanceStyle,
  handleStyleChange,
  handleStyleChange_
) where

import Control.Applicative ((<|>))
import Control.Lens ((&), (^.), (<>~))
import Data.Bits (xor)
import Data.Default
import Data.Maybe

import qualified Data.Sequence as Seq

import Monomer.Core
import Monomer.Event
import Monomer.Graphics
import Monomer.Widgets.Util.Widget

import qualified Monomer.Lens as L

type IsHovered s e = WidgetEnv s e -> WidgetInstance s e -> Bool

type GetBaseStyle s e
  = WidgetEnv s e
  -> WidgetInstance s e
  -> Maybe Style

newtype StyleChangeCfg = StyleChangeCfg {
  _sccHandleCursorEvt :: SystemEvent -> Bool
}

instance Default StyleChangeCfg where {
  def = StyleChangeCfg {
    _sccHandleCursorEvt = isOnEnter
  }
}

-- Do not use in findByPoint
activeStyle :: WidgetEnv s e -> WidgetInstance s e -> StyleState
activeStyle wenv inst = activeStyle_ isHovered wenv inst

activeStyle_ :: IsHovered s e -> WidgetEnv s e -> WidgetInstance s e -> StyleState
activeStyle_ isHoveredFn wenv inst = fromMaybe def styleState where
  Style{..} = _wiStyle inst
  mousePos = wenv ^. L.inputStatus . L.mousePos
  isEnabled = _wiEnabled inst
  isHover = isHoveredFn wenv inst
  isFocus = isFocused wenv inst
  styleState
    | not isEnabled = _styleDisabled
    | isHover && isFocus = _styleHover <> _styleFocus
    | isHover = _styleHover
    | isFocus = _styleFocus
    | otherwise = _styleBasic

focusedStyle :: WidgetEnv s e -> WidgetInstance s e -> StyleState
focusedStyle wenv inst = focusedStyle_ isHovered wenv inst

focusedStyle_ :: IsHovered s e -> WidgetEnv s e -> WidgetInstance s e -> StyleState
focusedStyle_ isHoveredFn wenv inst = fromMaybe def styleState where
  Style{..} = _wiStyle inst
  isHover = isHoveredFn wenv inst
  styleState
    | isHover = _styleHover <> _styleFocus
    | otherwise = _styleFocus

activeTheme :: WidgetEnv s e -> WidgetInstance s e -> ThemeState
activeTheme wenv inst = activeTheme_ isHovered wenv inst

activeTheme_ :: IsHovered s e -> WidgetEnv s e -> WidgetInstance s e -> ThemeState
activeTheme_ isHoveredFn wenv inst = themeState where
  theme = _weTheme wenv
  mousePos = wenv ^. L.inputStatus . L.mousePos
  isEnabled = _wiEnabled inst
  isHover = isHoveredFn wenv inst
  isFocus = isFocused wenv inst
  themeState
    | not isEnabled = _themeDisabled theme
    | isHover = _themeHover theme
    | isFocus = _themeFocus theme
    | otherwise = _themeBasic theme

initInstanceStyle
  :: GetBaseStyle s e
  -> WidgetEnv s e
  -> WidgetInstance s e
  -> WidgetInstance s e
initInstanceStyle getBaseStyle wenv inst = newInst where
  instStyle = mergeBasicStyle $ _wiStyle inst
  baseStyle = mergeBasicStyle $ fromMaybe def (getBaseStyle wenv inst)
  themeStyle = baseStyleFromTheme (_weTheme wenv)
  newInst = inst {
    _wiStyle = themeStyle <> baseStyle <> instStyle
  }

handleStyleChange
  :: WidgetEnv s e
  -> Path
  -> SystemEvent
  -> StyleState
  -> Maybe (WidgetResult s e)
  -> WidgetInstance s e
  -> Maybe (WidgetResult s e)
handleStyleChange wenv target evt style result inst = newResult where
  newResult = handleStyleChange_ wenv target evt style result def inst

handleStyleChange_
  :: WidgetEnv s e
  -> Path
  -> SystemEvent
  -> StyleState
  -> Maybe (WidgetResult s e)
  -> StyleChangeCfg
  -> WidgetInstance s e
  -> Maybe (WidgetResult s e)
handleStyleChange_ wenv target evt style result cfg inst = newResult where
  baseResult = fromMaybe (resultWidget inst) result
  sizeReqs = handleSizeChange wenv target evt cfg inst
  cursorReqs = handleCursorChange wenv target evt style cfg inst
  reqs = sizeReqs ++ cursorReqs
  newResult
    | not (null reqs) = Just (baseResult & L.requests <>~ Seq.fromList reqs)
    | otherwise = result

handleSizeChange
  :: WidgetEnv s e
  -> Path
  -> SystemEvent
  -> StyleChangeCfg
  -> WidgetInstance s e
  -> [WidgetRequest s]
handleSizeChange wenv target evt cfg inst = reqs where
  -- Hover
  mousePos = wenv ^. L.inputStatus . L.mousePos
  mousePosPrev = wenv ^. L.inputStatus . L.mousePosPrev
  vp = inst ^. L.viewport
  vpChanged = pointInRect mousePos vp `xor` pointInRect mousePosPrev vp
  hoverChanged = vpChanged && (isOnEnter evt || isOnLeave evt)
  -- Focus
  focusChanged = isOnFocus evt || isOnBlur evt
  -- Size
  checkSize = hoverChanged || focusChanged
  instReqs = widgetGetSizeReq (_wiWidget inst) wenv inst
  oldSizeReqW = inst ^. L.sizeReqW
  oldSizeReqH = inst ^. L.sizeReqH
  newSizeReqW = instReqs ^. L.sizeReqW
  newSizeReqH = instReqs ^. L.sizeReqH
  sizeReqChanged = oldSizeReqW /= newSizeReqW || oldSizeReqH /= newSizeReqH
  -- Result
  resizeReq = [ ResizeWidgets | checkSize && sizeReqChanged ]
  enterReq = [ RenderOnce | isOnEnter evt ]
  reqs = resizeReq ++ enterReq

handleCursorChange
  :: WidgetEnv s e
  -> Path
  -> SystemEvent
  -> StyleState
  -> StyleChangeCfg
  -> WidgetInstance s e
  -> [WidgetRequest s]
handleCursorChange wenv target evt style cfg inst = reqs where
  -- Cursor
  isCursorEvt = _sccHandleCursorEvt cfg
  isTarget = _wiPath inst == target
  curIcon = wenv ^. L.currentCursor
  notInOverlay = isJust (wenv ^. L.overlayPath) && not (isInOverlay wenv inst)
  newIcon
    | notInOverlay = CursorArrow
    | otherwise = fromMaybe CursorArrow (_sstCursorIcon style)
  setCursor = isTarget && newIcon /= curIcon && (isCursorEvt evt || notInOverlay)
  -- Result
  reqs = [ SetCursorIcon newIcon | setCursor ]

baseStyleFromTheme :: Theme -> Style
baseStyleFromTheme theme = style where
  style = Style {
    _styleBasic = fromThemeState (_themeBasic theme),
    _styleHover = fromThemeState (_themeHover theme),
    _styleFocus = fromThemeState (_themeFocus theme),
    _styleDisabled = fromThemeState (_themeDisabled theme)
  }
  fromThemeState tstate = Just $ def {
    _sstFgColor = Just $ _thsFgColor tstate,
    _sstHlColor = Just $ _thsHlColor tstate,
    _sstText = Just $ _thsText tstate
  }

mergeBasicStyle :: Style -> Style
mergeBasicStyle st = newStyle where
  newStyle = Style {
    _styleBasic = _styleBasic st,
    _styleHover = _styleBasic st <> _styleHover st,
    _styleFocus = _styleBasic st <> _styleFocus st,
    _styleDisabled = _styleBasic st <> _styleDisabled st
  }

isInOverlay :: WidgetEnv s e -> WidgetInstance s e -> Bool
isInOverlay wenv inst = maybe False isPrefix (wenv ^. L.overlayPath) where
  path = _wiPath inst
  isPrefix overlayPath = Seq.take (Seq.length overlayPath) path == overlayPath
