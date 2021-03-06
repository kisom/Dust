{-# LANGUAGE BangPatterns, DeriveGeneric, DefaultSignatures #-}
module Dust.Model.Huffman
(
   HuffmanTree,
   encode,
   decode,
   bitpack,
   bitunpack,
   padToEight,
   codes,
   fileToTree,
   countsToTree
)
where

import GHC.Generics
import Data.Serialize hiding (encode, decode)

import Data.Word
import Data.Char (intToDigit)
import Data.List (insertBy, foldl', sortBy)
import Data.Maybe (fromJust)
import Data.Ord (comparing)
import qualified Data.Binary.BitPut        as P
import qualified Data.Binary.Strict.BitGet as G
import qualified Data.ByteString           as S
import qualified Data.ByteString.Lazy      as B
import qualified Data.Map                  as M

--------------------------------------------------

data HuffmanTree a
  = LeafNode a Int
  | InternalNode Int (HuffmanTree a) (HuffmanTree a)
  deriving (Generic)
instance (Serialize a) => Serialize (HuffmanTree a)

-- build a multiline string representation of a huffman tree
instance Show a => Show (HuffmanTree a) where
  show =
      go ""
    where
      spaces = map (const ' ')
      paren s = "(" ++ s ++ ")"
      go ss (LeafNode s o) = "--" ++ paren (show o) ++ show s ++ "\n"
      go ss (InternalNode o l r) =
          let root  = "--" ++ paren (show o) ++ "-+"
              ss' = ss ++ tail (spaces root)
              lbranch = go (ss' ++ "|") l
              rbranch = go (ss' ++ " ") r
          in root ++ lbranch
                  ++ ss' ++ "|\n"
                  ++ ss' ++ "`"
                  ++ rbranch

frequency :: HuffmanTree a -> Int
frequency (LeafNode     _ x  ) = x
frequency (InternalNode x _ _) = x

-- build a huffman tree bototm-up from a list of symbols sorted by frequency
sortedHuffman :: [(a,Int)] -> HuffmanTree a
sortedHuffman =
    -- first, convert each tuple into a Leaf, then combine
    combine . map toLeaf
  where
    -- repeatedly combine lowest frequency trees and reinsert the result into
    -- the frequency ordered list
    -- note: a priority queue could help
    combine [t] = t
    combine (ta:tb:ts) = combine . insertBy (comparing frequency) (merge ta tb) $ ts
    -- make an internal node from two trees. the frequency is the sum of the
    -- two trees frequencies
    merge ta tb = InternalNode (frequency ta + frequency tb) ta tb
    -- make a Leaf from a symbol,freq tuple
    toLeaf = uncurry LeafNode

-- traverse the huffman tree generating a map from the symbol to its huffman
-- tree path (where False is left, and True is right)
codes :: Ord a => HuffmanTree a -> M.Map a [Bool]
codes =
    M.fromList . go []
  where
    -- leaf nodes mark the end of a path to a symbol
    go p (LeafNode s _) = [(s,reverse p)]
    -- traverse both branches and accumulate a reverse path
    go p (InternalNode _ l r) = go (False:p) l ++ go (True:p) r

-- from a table mapping symbols to their corresponding huffman tree bit paths,
-- replace each instance of a symbol with its bit path
encode :: Ord a => M.Map a [Bool] -> [a] -> [Bool]
encode tbl =
    concatMap get
  where
    get x = fromJust (M.lookup x tbl)

-- from a list of bits, navigate a given huffman tree and emit its decoded
-- symbol when reaching a Leaf
decode :: HuffmanTree a -> [Bool] -> [a]
decode t0 xs0 =
    go t0 xs0
  where
    -- reached leaf, emit symbol
    go (LeafNode s _) bs = s : go t0 bs
    -- choose path based on bit
    go (InternalNode _ l r) (b:bs)
      | not b     = go l bs
      | otherwise = go r bs
    go _ [] = []

--------------------------------------------------

-- count the number of instances each symbol occurs in a list
histogram :: Ord a => [a] -> [(a,Int)]
histogram xs =
    M.toList . foldl' insert M.empty $ xs
  where
    insert a k = M.insertWith' (+) k 1 a

swap :: (a,b) -> (b,a)
swap ~(a,b) = (b,a)

showBits :: [Bool] -> String
showBits = map (intToDigit . fromEnum)

--------------------------------------------------

bitpack :: [Bool] -> B.ByteString
bitpack = P.runBitPut . mapM_ P.putBit

bitunpack :: S.ByteString -> Either String [Bool]
bitunpack bs0 =
    G.runBitGet bs0 $ go []
  where
    go a = do
      e <- G.isEmpty
      if e
        then return (reverse a)
        else G.getBit >>= go . (:a)

--------------------------------------------------

padToEight :: [Bool] -> [Bool]
padToEight bits =
    let len = length bits
        rem = len `mod` 8
        extra = 8-rem
        padding = replicate extra False
    in bits ++ padding

fileToTree :: FilePath -> IO (HuffmanTree Word8)
fileToTree path = do
    contents <- B.readFile path
    return $ bytesToTree $ B.unpack contents

bytesToTree :: [Word8] -> (HuffmanTree Word8)
bytesToTree text =
    let frequencies = histogram text
        sortedFrequencies = sortBy (comparing swap) frequencies
    in sortedHuffman sortedFrequencies

countsToTree :: [(Word8, Int)] -> (HuffmanTree Word8)
countsToTree frequencies =
    let sortedFrequencies = sortBy (comparing swap) frequencies
    in sortedHuffman sortedFrequencies
