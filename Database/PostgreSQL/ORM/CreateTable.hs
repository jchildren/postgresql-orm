{-# LANGUAGE CPP, FlexibleInstances, FlexibleContexts, TypeOperators #-}
{-# LANGUAGE DeriveGeneric, OverloadedStrings, MultiParamTypeClasses #-}

module Database.PostgreSQL.ORM.CreateTable where

import qualified Data.ByteString as S
import qualified Data.ByteString.Char8 as S8
import Data.Int
import Data.Monoid
import Database.PostgreSQL.Simple
import Database.PostgreSQL.Simple.Types
import GHC.Generics

import Database.PostgreSQL.ORM.Model
import Database.PostgreSQL.ORM.Relationships
import Database.PostgreSQL.ORM.SqlType


class GDefTypes f where
  gDefTypes :: f p -> [S.ByteString]
instance (SqlType c) => GDefTypes (K1 i c) where
  gDefTypes ~(K1 c) = [sqlType c]
instance (GDefTypes a, GDefTypes b) => GDefTypes (a :*: b) where
  gDefTypes ~(a :*: b) = gDefTypes a ++ gDefTypes b
instance (GDefTypes f) => GDefTypes (M1 i c f) where
  gDefTypes ~(M1 fp) = gDefTypes fp


createTableWithTypes :: (Model a, Generic a, GDefTypes (Rep a)) =>
                        [(S.ByteString, S.ByteString)] -> a -> Query
createTableWithTypes except a = Query $ S.concat [
  "create table ", quoteIdent $ modelTable info, " ("
  , S.intercalate ", " (go types names), ")"
  ]
  where types = gDefTypes $ from a
        info = modelToInfo a
        names = modelColumns info
        go (t:ts) (n:ns)
          | Just t' <- lookup n except = quoteIdent n <> " " <> t' : go ts ns
          | otherwise = quoteIdent n <> " " <> t : go ts ns
        go [] [] = []
        go _ _ = error $ "createTable: " ++ S8.unpack (modelTable info)
                 ++ " has incorrect number of columns"


class (Model a, Generic a, GDefTypes (Rep a)) => CreateTable a where
  createTableTypes :: ModelInfo a -> [(S.ByteString, S.ByteString)]
  createTableTypes _ = []

createTable :: (CreateTable a) => a -> Query
createTable a = createTableWithTypes (createTableTypes $ modelToInfo a) a

data Foo = Foo {
  foo_key :: !DBKey
  , foo_name :: String
  -- , parent :: !(Maybe (DBRef Bar))
  } deriving (Show, Generic)
                                    
instance Model Foo

mkFoo :: String -> Foo
mkFoo = Foo NullKey

data Bar = Bar {
    bar_key :: !DBKey
  , bar_none :: !(Maybe Int32)
  , bar_name :: !String
  , bar_parent :: !(Maybe (DBRef Bar))
  } deriving (Show, Generic)

instance Model Bar

instance CreateTable Bar where
  createTableTypes _ = [("barString", "varchar(16)")]

mkBar :: String -> Bar
mkBar msg = Bar NullKey (Just n) msg Nothing
  where n = foldl (+) 0 $ map (toEnum . fromEnum) msg

instance HasMany Bar Bar

data Joiner = Joiner {
    jkey :: !DBKey
  , jcomment :: !String
  , jfoo :: (DBRef Foo)
  , jbar :: !(Maybe (DBRef Bar))
  } deriving (Show, Generic)
instance Model Joiner


instance Joinable Foo Bar where
  joinTable = (joinThroughModel (undefined :: Joiner)) {
    jtAllowModification = True }
instance Joinable Bar Foo where
  joinTable = joinReverse

bar :: Bar
bar = Bar NullKey (Just 44) "hi" Nothing

mkc :: IO Connection
mkc = connectPostgreSQL ""

bar' :: Bar
bar' = Bar NullKey (Just 75) "bye" Nothing


x :: Maybe Int32
x = Just 5

y :: Maybe Float
y = Just 6.0
