
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedStrings #-}

-- | This module contains the functions related to @Error@ type,
-- in particular, to @tidyError@ using a solution, and @pprint@ errors.

module Language.Haskell.Liquid.Errors (tidyError) where


import           Control.Applicative                 ((<$>), (<*>))
import           Control.Exception                   (Exception (..))
import           Data.Aeson
import           Data.Hashable
import qualified Data.HashMap.Strict                 as M
import qualified Data.HashSet                        as S
import           Data.List                           (intersperse)
import           Data.Maybe                          (fromMaybe, maybeToList)
import           Data.Monoid                         hiding ((<>))
import           Language.Fixpoint.Misc              hiding (intersperse)
import           Language.Fixpoint.Types
import           Language.Haskell.Liquid.PrettyPrint
import           Language.Haskell.Liquid.RefType
import           Language.Haskell.Liquid.Tidy
import           Language.Haskell.Liquid.Types
import           SrcLoc                              (SrcSpan)
import           Text.PrettyPrint.HughesPJ

------------------------------------------------------------------------
tidyError :: FixSolution -> Error -> Error
------------------------------------------------------------------------
tidyError sol = tidyContext sol
              . fmap (tidySpecType Full) . applySolution sol

tidyContext s err@(ErrSubType {})
  = err { ctx = shrinkREnv xs $ ctx err }
    where
      xs = syms tA ++ syms tE
      tA = tact err
      tE = texp err

tidyContext _ err
  = err

shrinkREnv xs m = M.fromList $ [(x, t) | x <- xs', t <- maybeToList (M.lookup x m)]
    where
      xs'       = expandFix deps xs
      deps y    = fromMaybe [] $ fmap (syms . rTypeReft) $ M.lookup y m

expandFix :: (Eq a, Hashable a) => (a -> [a]) -> [a] -> [a]
expandFix f xs          = S.toList $ go S.empty xs
  where
    go seen []          = seen
    go seen (x:xs)
      | x `S.member` seen = go seen xs
      | otherwise         = go (S.insert x seen) (f x ++ xs)


------------------------------------------------------------------------
-- | Pretty Printing Error Messages ------------------------------------
------------------------------------------------------------------------

-- Need to put this here intead of in Types, because it depends on the
-- printer for SpecTypes, which lives in this module.

instance PPrint Error where
  pprint = ppError . fmap (rtypeDoc Lossy)
            -- undefined
            -- ppError . ppr_rtype

instance Show Error where
  show = showpp

instance Exception Error
instance Exception [Error]

------------------------------------------------------------------------
ppError :: (PPrint a) => TError a -> Doc
------------------------------------------------------------------------

ppError e = ppError' (pprintE $ errSpan e) e
pprintE l = pprint l <> text ": Error:"

nests n    = foldr (\d acc -> nest n (d $+$ acc)) empty

sepVcat d ds = vcat $ intersperse d ds
blankLine    = sizedText 5 " "

------------------------------------------------------------------------
ppError' :: (PPrint a) => Doc -> TError a -> Doc
-----------------------------------------------------------------------


ppError' dSp (ErrAssType _ OTerm s r)
  = dSp <+> text "Termination Check"

ppError' dSp (ErrAssType _ OInv s r)
  = dSp <+> text "Invariant Check"

ppError' dSp (ErrSubType _ s c tA tE)
  = dSp <+> text "Liquid Type Mismatch"
--      DO NOT DELETE EVER!
        $+$ sepVcat blankLine
              [ nests 2 [text "Required Type", pprint tE]
              , nests 2 [text "Actual Type"  , pprint tA]
              , nests 2 [text "In Context"   , pprint c ]]


ppError' dSp (ErrParse _ _ e)
  = dSp <+> text "Cannot parse specification:"
    $+$ (nest 4 $ pprint e)

ppError' dSp (ErrTySpec _ v t s)
  = dSp <+> text "Bad Type Specification"
    $+$ (pprint v <+> dcolon <+> pprint t)
    $+$ (nest 4 $ pprint s)

ppError' dSp (ErrInvt _ t s)
  = dSp <+> text "Bad Invariant Specification"
    $+$ (nest 4 $ text "invariant " <+> pprint t $+$ pprint s)

ppError' dSp (ErrIAl _ t s)
  = dSp <+> text "Bad Using Specification"
    $+$ (nest 4 $ text "as" <+> pprint t $+$ pprint s)

ppError' dSp (ErrIAlMis _ t1 t2 s)
  = dSp <+> text "Incompatible Using Specification"
    $+$ (nest 4 $ (text "using" <+> pprint t1 <+> text "as" <+> pprint t2) $+$ pprint s)

ppError' dSp (ErrMeas _ t s)
  = dSp <+> text "Bad Measure Specification"
    $+$ (nest 4 $ text "measure " <+> pprint t $+$ pprint s)

ppError' dSp (ErrDupSpecs _ v ls)
  = dSp <+> text "Multiple Specifications for" <+> pprint v <> colon
    $+$ (nest 4 $ vcat $ pprint <$> ls)

ppError' dSp (ErrDupAlias _ k v ls)
  = dSp <+> text "Multiple Declarations! "
    $+$ (nest 2 $ text "Multiple Declarations of" <+> pprint k <+> ppVar v $+$ text "Declared at:")
    <+> (nest 4 $ vcat $ pprint <$> ls)

ppError' dSp (ErrGhc _ s)
  = dSp <+> text "GHC Error"
    $+$ (nest 4 $ pprint s)

ppError' dSp (ErrMismatch _ x τ t)
  = dSp <+> text "Specified Type Does Not Refine Haskell Type for" <+> pprint x
    $+$ text "Haskell:" <+> pprint τ
    $+$ text "Liquid :" <+> pprint t

ppError' dSp (ErrSaved _ s)
  = dSp <+> s

ppError' _ (ErrOther _ s)
  = text "Panic!" <+> nest 4 (pprint s)


ppVar v = text "`" <> pprint v <> text "'"

instance ToJSON Error where
  toJSON e = object [ "pos" .= (errSpan e)
                    , "msg" .= (render $ ppError' empty e)
                    ]

instance FromJSON Error where
  parseJSON (Object v) = errSaved <$> v .: "pos"
                                  <*> v .: "msg"
  parseJSON _          = mempty


errSaved :: SrcSpan -> String -> Error
errSaved x = ErrSaved x . text
