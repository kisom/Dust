{-# LANGUAGE DeriveGeneric, DefaultSignatures #-} -- For automatic generation of cereal put and get

module Dust.Crypto.DustCipher
(
  EncryptionKey(..),
  IV(..),
  Plaintext(..),
  Ciphertext(..),

  encrypt,
  decrypt,
  createIV
) where

import GHC.Generics
import Data.ByteString
import Data.Serialize
import Codec.Crypto.AES
import System.Entropy

import Dust.Crypto.Keys

data EncryptionKey = EncryptionKey ByteString deriving (Show, Eq)
newtype IV = IV ByteString deriving (Show, Eq, Generic)
newtype Plaintext = Plaintext ByteString deriving (Show, Eq, Generic)
newtype Ciphertext = Ciphertext ByteString deriving (Show, Eq, Generic)

instance Serialize IV
instance Serialize Plaintext
instance Serialize Ciphertext

encrypt :: EncryptionKey -> IV -> Plaintext -> Ciphertext
encrypt (EncryptionKey key) (IV iv) (Plaintext plaintext) = Ciphertext (crypt' CTR key iv Encrypt plaintext)

decrypt :: EncryptionKey -> IV -> Ciphertext -> Plaintext
decrypt (EncryptionKey key) (IV iv) (Ciphertext ciphertext) = Plaintext (crypt' CTR key iv Decrypt ciphertext)

createIV :: IO (IV)
createIV = do
    entropy <- getEntropy 16
    return (IV entropy)
