{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE NamedFieldPuns #-}

module LolHub.Graphql.Api.LobbyApi (lobbyApi, USEREVENT) where

import           Core.DB.MongoUtil (run, (<<-))
import           LolHub.Graphql.Types
import           LolHub.Graphql.Resolver
import qualified LolHub.Domain.Lobby as Lobby
import qualified LolHub.Domain.User as User
import qualified LolHub.DB.Actions as Actions
import           Text.Read (readMaybe)
import           Data.Text (pack, unpack, Text)
import           Data.ByteString.Lazy (ByteString)
import           Data.Either.Utils
import           Data.Morpheus.Document (importGQLDocument)
import           Data.Morpheus (interpreter)
import           Data.Morpheus.Types (MUTATION,QUERY,SUBSCRIPTION,Event(..), GQLRootResolver(..), IOMutRes
                                    , IOSubRes, IORes, ResolveM, ResolveQ
                                    , ResolveS, Undefined(..), Resolver(..)
                                    , liftEither)
import           Control.Monad.Trans (lift)
import           Database.MongoDB (Pipe, ObjectId, genObjectId)

importGQLDocument "src/LolHub/Graphql/Query/Lobby.gql"

----- API ------
lobbyApi :: Pipe -> Maybe User.SessionE -> ByteString -> IO ByteString
lobbyApi pipe session = interpreter $ lobbyGqlRoot pipe session

lobbyGqlRoot :: Pipe
             -> Maybe User.SessionE
             -> GQLRootResolver IO USEREVENT Undefined Mutation Subscription
lobbyGqlRoot pipe session =
  GQLRootResolver { queryResolver, mutationResolver, subscriptionResolver }
  -------------------------------------------------------------

    where
      queryResolver = Undefined

      mutationResolver = Mutation { create = resolveCreateLobby session pipe
                                  , join = resolveJoinLobby session pipe
                                  }

      subscriptionResolver =
        Subscription { joined = resolveJoinedLobby session pipe }

----- QUERY RESOLVERS -----
resolveHelloWorld :: Value QUERY String
resolveHelloWorld = return "helloWorld" -- //TODO: remove this, when there are other queries

----- MUTATION RESOLVERS -----
resolveCreateLobby
  :: Maybe User.SessionE -> Pipe -> CreateArgs -> ResolveM USEREVENT IO Lobby
resolveCreateLobby session pipe args = liftEither
  (resolveCreateLobby' session pipe args)
  where
    resolveCreateLobby' :: Maybe User.SessionE -> Pipe -> CreateArgs -> IO(EitherObject MUTATION USEREVENT String Lobby)
    resolveCreateLobby' session pipe args = do
      oid <- genObjectId
      uname <- return $ User._uname <$> session
      creator <- run (Actions.getUserByName <<- uname) pipe
      lobby <- return $ (Lobby.createLobby lobbyKind oid) =<< creator
      run (Actions.insertLobby <<- lobby) pipe
      return
        (maybeToEither "Invalid Session" $ resolveLobby <$> lobby <*> creator)

    lobbyKind = toLobbyKindE $ kind args :: Lobby.LobbyKindE

resolveJoinLobby
  :: Maybe User.SessionE -> Pipe -> JoinArgs -> ResolveM USEREVENT IO Lobby
resolveJoinLobby session pipe JoinArgs { lobby, team } = do
  value <- liftEither (resolveJoinLobby' session pipe lobby team)
  MutResolver $ return ([Event [USER] (Content { contentID = 12 })], value)
  where
    resolveJoinLobby' :: Maybe User.SessionE
                      -> Pipe
                      -> Text
                      -> TeamColor
                      -> IO(EitherObject MUTATION USEREVENT String Lobby)
    resolveJoinLobby' session pipe lobbyId tc = do
      uname <- return $ User._uname <$> session
      user <- run (Actions.getUserByName <<- uname) pipe
      lid <- return $ (readMaybe $ unpack lobbyId :: Maybe ObjectId)
      lobby <- run (Actions.findLobby <<- lid) pipe
      lobby' <- return
        $ Lobby.joinLobby <$> lobby <*> user <*> (return $ toTeamColorE tc)
      result <- run
        (Actions.updateLobby <<- lobby')
        pipe -- //TODO: magically worked, after a few commits, why...keep an eye on that !!!
      return
        (maybeToEither "Invalid Session" $ resolveLobby <$> lobby' <*> user)

resolveJoinedLobby :: Maybe User.SessionE
                   -> Pipe
                   -> JoinedArgs
                   -> ResolveS USEREVENT IO UserJoined
resolveJoinedLobby session pipe args =
  SubResolver { subChannels = [USER], subResolver = subResolver }
  where
    subResolver (Event [USER] content) = lift (resolveJoinedLobby' content)

    resolveJoinedLobby' :: Content -> IO (Object QUERY USEREVENT UserJoined)
    resolveJoinedLobby' content = return
      UserJoined { username =
                     return $ pack $ show $ contentID content
                 }