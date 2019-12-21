{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}

module Lolhub.Connection.DB.Coll.User (getAllUsers, insertUser, User(..)) where

import           Database.MongoDB (Action, Pipe, Collection, Document, Document
                                 , Value, access, close, connect, delete
                                 , exclude, find, findOne, host, insert
                                 , insertMany, master, project, rest, select
                                 , sort, (=:))
import           Control.Monad.Trans (liftIO)
import qualified Lolhub.Connection.DB.Mongo (run)
import           Control.Concurrent.MonadIO
import           GHC.Generics
import           Data.Bson.Mapping
import           Data.Data (Typeable)
import           Control.Monad.Trans.Reader (mapReaderT)
import           Control.Monad.Trans.Class (lift)

data User = User { username :: String
                 , email :: String
                 , firstname :: String
                 , lastname :: String
                 , password :: String
                 }
  deriving (Generic, Typeable, Show, Read, Eq, Ord)

$(deriveBson ''User)

collection :: Collection
collection = "user"

getUser :: String -> Action IO (Maybe User)
getUser username = mapReaderT (fromBSON) result
  where
    result = findOne (select ["username" =: username] collection)
      :: Action IO (Maybe Document)

    fromBSON = liftIO (fromBson =<<) :: MonadIO m => IO(m a) ->IO( m b)

insertUser :: User -> Action IO Value
insertUser user = insert collection (toBson user)