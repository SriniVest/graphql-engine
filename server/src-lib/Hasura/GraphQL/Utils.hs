{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}

module Hasura.GraphQL.Utils
  ( onNothing
  , showName
  , showNamedTy
  , throwVE
  , getBaseTy
  , mapFromL
  , groupTuples
  , groupListWith
  , mkMapWith
  , onLeft
  , showNames
  , isValidName
  ) where

import           Hasura.RQL.Types
import           Hasura.Prelude

import qualified Data.HashMap.Strict           as Map
import qualified Data.List.NonEmpty            as NE
import qualified Data.Text                     as T
import qualified Language.GraphQL.Draft.Syntax as G
import qualified Text.Regex                    as R

showName :: G.Name -> Text
showName name = "\"" <> G.unName name <> "\""

onNothing :: (Monad m) => Maybe a -> m a -> m a
onNothing m act = maybe act return m

throwVE :: (MonadError QErr m) => Text -> m a
throwVE = throw400 ValidationFailed

showNamedTy :: G.NamedType -> Text
showNamedTy nt =
  "'" <> G.showNT nt <> "'"

getBaseTy :: G.GType -> G.NamedType
getBaseTy = \case
  G.TypeNamed n     -> n
  G.TypeList lt     -> getBaseTyL lt
  G.TypeNonNull nnt -> getBaseTyNN nnt
  where
    getBaseTyL = getBaseTy . G.unListType
    getBaseTyNN = \case
      G.NonNullTypeList lt -> getBaseTyL lt
      G.NonNullTypeNamed n -> n

mapFromL :: (Eq k, Hashable k) => (a -> k) -> [a] -> Map.HashMap k a
mapFromL f l =
  Map.fromList [(f v, v) | v <- l]

groupListWith
  :: (Eq k, Hashable k, Foldable t, Functor t)
  => (v -> k) -> t v -> Map.HashMap k (NE.NonEmpty v)
groupListWith f l =
  groupTuples $ fmap (\v -> (f v, v)) l

groupTuples
  :: (Eq k, Hashable k, Foldable t)
  => t (k, v) -> Map.HashMap k (NE.NonEmpty v)
groupTuples =
  foldr groupFlds Map.empty
  where
    groupFlds (k, v) m = case Map.lookup k m of
      Nothing -> Map.insert k (v NE.:| []) m
      Just s  -> Map.insert k (v NE.<| s) m

-- either duplicate keys or the map
mkMapWith
  :: (Eq k, Hashable k, Foldable t, Functor t)
  => (v -> k) -> t v -> Either (NE.NonEmpty k) (Map.HashMap k v)
mkMapWith f l =
  case NE.nonEmpty dups of
    Just dupsNE -> Left dupsNE
    Nothing     -> Right $ Map.map NE.head mapG
  where
    mapG = groupListWith f l
    dups = Map.keys $ Map.filter ((> 1) . length) mapG

onLeft :: (Monad m) => Either e a -> (e -> m a) -> m a
onLeft e f = either f return e

showNames :: (Foldable t) => t G.Name -> Text
showNames names =
  T.intercalate ", " $ map G.unName $ toList names

-- Ref: http://facebook.github.io/graphql/June2018/#sec-Names
isValidName :: G.Name -> Bool
isValidName =
  isJust . R.matchRegex regex . T.unpack . G.unName
  where
    regex = R.mkRegex "^[_a-zA-Z][_a-zA-Z0-9]*$"
