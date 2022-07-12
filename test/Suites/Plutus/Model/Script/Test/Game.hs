module Suites.Plutus.Model.Script.Test.Game (
  tests,
  initGuessGame,
  makeGuessGame,
) where

import Control.Monad (unless)

import Data.Either
import Data.Functor (void)
import Prelude

import Test.Tasty
import Test.Tasty.HUnit

import Plutus.V1.Ledger.Api
import PlutusTx.Prelude qualified as Plutus
import Suites.Plutus.Model.Script.Onchain.Game
import Suites.Plutus.Model.Script.Onchain.Game.Script
import Suites.Plutus.Model.Util

import Plutus.Test.Model

tests :: BchConfig -> TestTree
tests cfg =
  testGroup
    "Game scripts"
    [ good "Init script (Guess game)" initGuessGame
    -- , good "Spend script (Guess game)" makeGuessGame
    -- , bad "Bad guess" badGuessGame
    ]
  where
    -- bad = check False
    good msg act = testNoErrorsTrace (adaValue 10_000_000) cfg msg act

initGuessGame :: Run ()
initGuessGame = do
  users <- setupUsers
  let u1 = head users
      answer = "secret"
      prize = adaValue 100
  initGame u1 prize answer
  val1 <- valueAt u1
  gameVal <- valueAt gameScript
  gameUtxos <- utxoAt gameScript
  let [(gameRef, gameOut)] = gameUtxos
  mDat <- datumAt @GameDatum gameRef
  unless
    (and
      [ val1 == adaValue 900
      , gameVal == prize
      , txOutValue gameOut == prize
      , mDat == Just (GuessHash $ Plutus.sha2_256 answer)
      ]) $ logError "Constraints violated"


badGuessGame :: Run Bool
badGuessGame = makeGuessGameBy gameSecret "bad guess"

makeGuessGame :: Run Bool
makeGuessGame = makeGuessGameBy gameSecret gameSecret

gameSecret :: BuiltinByteString
gameSecret = "secret"

makeGuessGameBy :: BuiltinByteString -> BuiltinByteString -> Run Bool
makeGuessGameBy secret answer = do
  users <- setupUsers
  let [u1, u2, _] = users
  initGame u1 (adaValue 100) secret
  postedTx <- guess u2 answer
  vals <- mapM valueAt users
  let [v1, v2, _] = vals
  isOk <- noErrors
  pure $ postedTx && isOk && v1 == adaValue 900 && v2 == adaValue 1100

initGame :: PubKeyHash -> Value -> BuiltinByteString -> Run ()
initGame pkh prize answer =
  checkBalance (gives pkh prize gameScript) $ do
    sp <- spend pkh prize
    tx <- signTx pkh $ initGameTx sp prize answer
    void $ sendTx tx

initGameTx :: UserSpend -> Value -> BuiltinByteString -> Tx
initGameTx usp val answer =
  mconcat
    [ userSpend usp
    , payToScript gameScript (GuessHash $ Plutus.sha2_256 answer) val
    ]

guess :: PubKeyHash -> BuiltinByteString -> Run Bool
guess pkh answer = do
  utxos <- utxoAt gameScript
  let [(gameRef, gameOut)] = utxos
  mDat <- datumAt @GameDatum gameRef
  case mDat of
    Just dat -> checkBalance (gives gameScript (txOutValue gameOut) pkh) $ do
      tx <- signTx pkh $ guessTx pkh gameRef (txOutValue gameOut) dat answer
      isRight <$> sendTx tx
    Nothing -> pure False

guessTx :: PubKeyHash -> TxOutRef -> Value -> GameDatum -> BuiltinByteString -> Tx
guessTx pkh gameRef gameVal dat answer =
  mconcat
    [ spendScript gameScript gameRef (Guess answer) dat
    , payToPubKey pkh gameVal
    ]
