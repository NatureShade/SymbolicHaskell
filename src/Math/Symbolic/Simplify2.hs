{-# LANGUAGE OverloadedStrings, QuasiQuotes, ViewPatterns #-}
module Math.Symbolic.Simplify2 where

import Math.Symbolic.Expression
import Math.Symbolic.M.QQ

import Data.Word
import Data.Maybe
import Data.List
import Data.Monoid
import Data.Ratio
import Control.Arrow
import qualified Data.Text as T
import Data.Text (Text)


converge :: (a -> a -> Bool) -> [a] -> a
converge p (x:ys@(y:_))
    | p x y     = y
    | otherwise = converge p ys


runFun :: (Eq a) => (a -> a) -> a -> a
runFun f a = converge (==) $ iterate f a



traverseMath :: (Math a -> Math a) -> Math a -> Math a
traverseMath f (Op op xs) = f . Op op $ (f . traverseMath f) <$> xs
traverseMath f x = f x


sortMath :: (Ord a) => Math a -> Math a
sortMath (Op "+" xs) = Op "+" $ sort xs
sortMath (Op "*" xs) = Op "*" $ sort xs
sortMath x = x

level :: (Fractional a, Real a) => Math a -> Math a
level [sym|_a1+_a2|] =  Op "+" $ level' (a1+a2)
    where
        level' [sym|(_a1+_a2)+_a3|] = concatMap level' [a1, a2, a3]
        level' [sym|_a1+(_a2+_a3)|] = concatMap level' [a1, a2, a3]
        level' [sym|_a1+_a2|]       = concatMap level' [a1, a2]
        level' x = [x]
level [sym|_a1*_a2|] = Op "*" $ level' (a1*a2)
    where
        level' [sym|(_a1*_a2)*_a3|] = concatMap level' [a1, a2, a3]
        level' [sym|_a1*(_a2*_a3)|] = concatMap level' [a1, a2, a3]
        level' [sym|_a1*_a2|]       = concatMap level' [a1, a2]
        level' x = [x]
level x = x


rational :: (Fractional a, Real a) => Math a -> Math a
rational x = case x of
    [sym|(_a1/_a2)/_a3|] -> a1 / (a2*a3)
    [sym|_a1/(_a2/_a3)|] -> (a1*a3) / a2
    Op "*" xs -> case getRat xs of
                     Just (x, y, xs) -> Op "*" (x:xs) / y
                     _ -> Op "*" xs
        where
            getRat ([sym|_a1/_a2|]:xs) = Just (a1, a2, xs)
            getRat (x:xs) = do
                            (x', y', xs') <- getRat xs
                            return (x', y', x:xs')
            getRat [] = Nothing
    _ -> x

commonMForm :: (Fractional a, Real a) => Math a -> Math a
commonMForm (Op "*" xs) = Op "*" $ fmap commonForm' xs
    where
        commonForm' [sym|_a1^_a2|] = a1**a2
        commonForm' x = x**1
commonMForm x = x


commonSForm :: (Fractional a, Real a) => Math a -> Math a
commonSForm (Op "+" xs) = Op "+" $ fmap commonForm' xs
    where
        commonForm' x@[sym|_n1*:_a1|] = x
        commonForm' x = level $ 1*x
commonSForm x = x


collectMLike :: (Fractional a, Real a) => Math a -> Math a
collectMLike (Op "*" xs) = Op "*" . concatMap addLike $ groupBy likeTerm xs
    where
        likeTerm [sym|_ax^_a1|] [sym|_ay^_a2|] = ax == ay
        likeTerm _ _ = False

        addLike ([sym|(_ab^_a1)|]:xs) = [ab ** sum (a1 : fmap getExp xs)]
        addLike x = x

        getExp [sym|_a1^_a2|] = a2
collectMLike x = x


collectSLike :: (Fractional a, Real a) => Math a -> Math a
collectSLike (Op "+" xs) = Op "+" . concatMap addLike $ groupBy likeTerm xs
    where
        likeTerm [sym|_n1*:_ax|] [sym|_n2*:_ay|] = ax == ay
        likeTerm _ _ = False

        addLike ([sym|(_n1*_ax)|]:xs) = [sum (Numeric n1 : fmap getNum xs) * ax]
        addLike x = x

        getNum [sym|_n1*_ax|] = Numeric n1

collectSLike x = x


likeTerms :: (Fractional a, Real a, Ord a) => Math a -> Math a
likeTerms = traverseMath collectSLike
          . traverseMath sortMath
          . traverseMath commonSForm
          . runFun simplifyConst
          . traverseMath collectMLike
          . traverseMath sortMath
          . traverseMath commonMForm
          . runFun simplifyConst


foldConst :: (Fractional a, Real a) => Math a -> Math a
foldConst [sym|_n1*:(_n2*_a1)|] = foldConst . Op "*" $ Numeric (n1*n2) : a1
foldConst [sym|_n1+:(_n2+_a1)|] = foldConst . Op "+" $ Numeric (n1+n2) : a1
foldConst x = x


reduce :: (Fractional a, Real a) => Math a -> Math a
reduce [sym|1*:_a1|] = reduce $ Op "*" a1
reduce [sym|0+:_a1|] = reduce $ Op "+" a1
reduce [sym|_a1^1|] = a1
reduce [sym|_a1^0|] = 0
reduce [sym|1^_a1|] = 1
reduce [sym|0^_a1|] = 0
reduce (Op "+" [x]) = x
reduce (Op "*" [x]) = x
reduce (Op op xs) = Op op $ filter (not . emptyOp) xs
    where
        emptyOp (Op op []) = True
        emptyOp _ = False
reduce x = x


expand :: (Fractional a, Real a) => Math a -> Math a
expand = traverseMath expand'
    where
        expand' (Op "*" xs) = Op "+" . fmap (Op "*") $ mapM fromSum xs
            where
                fromSum (Op "+" xs) = xs
                fromSum x = [x]
        expand' [sym|(:*_a1)^_a2|] = Op "*" $ (**a2) <$> a1
        expand' x = x


simplifyConst :: (Fractional a, Real a, Ord a) => Math a -> Math a
simplifyConst = runFun (traverseMath foldConst)
              . runFun (traverseMath reduce)
              . traverseMath sortMath


simplify' :: (Fractional a, Real a, Ord a) => Math a -> Math a
simplify' = runFun simplifyConst
          . likeTerms
          . runFun (traverseMath rational)
          . traverseMath sortMath
          . traverseMath level

simplify = runFun simplify'

likeTerms' :: (Ord a, Fractional a, Real a) => Math a -> Math a
likeTerms' = runFun (traverseMath reduce)
          . traverseMath collectSLike
          . traverseMath commonSForm
          . runFun (traverseMath reduce)
          . traverseMath collectMLike
          . traverseMath commonMForm



simplify'' :: (Fractional a, Real a, Ord a) => Math a -> Math a
simplify'' = sortMath
          -- . expand
           . traverseMath foldConst
           . runFun (traverseMath rational)
           . sortMath
           . traverseMath level
           . likeTerms'
           . runFun (traverseMath reduce)
           . sortMath
           . runFun (traverseMath rational)
           . sortMath
           . traverseMath level

x = Sym "x"
y = Sym "y"
z = Sym "z"

a = Sym "a"
b = Sym "b"
c = Sym "c"
d = Sym "d"
e = Sym "e"
f = Sym "f"
