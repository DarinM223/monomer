{-# LANGUAGE TemplateHaskell #-}

module KeysComposite (
  KeysCompEvent(..),
  keysComposite
) where

import Debug.Trace

import Control.Concurrent (threadDelay)
import Control.Lens hiding (Empty, (|>), (<|))
import Control.Monad (forM_)

import Data.Default
import Data.Sequence (Seq(..), (|>))
import Data.Text (Text)
import Data.Typeable (Typeable)
import TextShow

import qualified Data.Sequence as Seq

import Monomer.Core.Style
import Monomer.Core.WidgetTypes
import Monomer.Core.Util
import Monomer.Graphics.Color
import Monomer.Widgets

data EditableItem = EditableItem {
  _itemId :: Text,
  _itemDesc :: Text
} deriving (Show, Eq)

newtype KeysCompState = KeysCompState {
  _items :: Seq EditableItem
} deriving (Show, Eq)

makeLenses ''EditableItem
makeLenses ''KeysCompState

data KeysCompEvent = RotateChildren
               deriving (Eq, Show)

initialState = KeysCompState {
  _items = Seq.fromList [
    EditableItem "1" "Text 1",
    EditableItem "2" "Text 2",
    EditableItem "3" "Text 3",
    EditableItem "4" "Text 4",
    EditableItem "5" "Text 5"
  ]
}

keysComposite :: WidgetInstance KeysCompState ep
keysComposite = composite "keysComposite" initialState Nothing handleKeysCompEvent buildKeysComp

handleKeysCompEvent model evt = case evt of
  RotateChildren -> [Model (model & items %~ rotateSeq)]

buildKeysComp model = trace "Created keys composite UI" $
  hgrid [
    button "Rotate" RotateChildren,
    vgrid $ fmap (editableItem model) [0..(length (_items model) - 1)]
  ]

editableItem model idx = widget where
  widgetKey = model ^. singular (items . ix idx . itemId)
  widget = hgrid [
      label $ "Item " <> showt idx,
      textField (singular $ items . ix idx . itemDesc)
    ] `key` widgetKey

rotateSeq Empty = Empty
rotateSeq (x :<| xs) = xs |> x
