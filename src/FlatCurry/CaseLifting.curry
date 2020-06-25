------------------------------------------------------------------------------
--- This module contains an implementation of a case lifter, i.e.,
--- an operation which lifts all nested cases (and also nested lets)
--- in a FlatCurry program into new operations.
---
--- NOTE: the new operations contain nonsense types, i.e., this transformation
--- should only be used if the actual function types are irrelevant!
---
--- @author Michael Hanus
--- @version June 2020
------------------------------------------------------------------------------

module FlatCurry.CaseLifting where

import List ( maximum, union )

import Control.Monad.Trans.State ( State, get, put, modify, evalState )
import FlatCurry.Goodies         ( allVars, funcName )
import FlatCurry.Types

------------------------------------------------------------------------------
--- Options for case/let/free lifting.
data LiftOptions = LiftOptions
  { liftCase :: Bool -- lift nested cases?
  , liftCArg :: Bool -- lift non-variable case arguments?
  }

--- Default options for lifting all nested case/let/free expressions.
defaultLiftOpts :: LiftOptions
defaultLiftOpts = LiftOptions True True

--- Default options for lifting no nested case/let/free expression.
defaultNoLiftOpts :: LiftOptions
defaultNoLiftOpts = LiftOptions False False

------------------------------------------------------------------------------
--- Options for case/let/free lifting.
data LiftState = LiftState
  { liftOpts  :: LiftOptions -- lifting options
  , currMod   :: String      -- name of current module
  , topFuncs  :: [String]    -- name of all origin top-level functions
  , liftFuncs :: [FuncDecl]  -- new functions generated by lifting
  , currFunc  :: String      -- name of current top-level function to be lifted
  , currIndex :: Int         -- index for generating new function names
  }

type LiftingState a = State LiftState a

-- Get lifting options from current state.
getOpts :: LiftingState LiftOptions
getOpts = get >>= return . liftOpts

-- Create a new function name from the current function w.r.t. a suffix.
genFuncName :: String -> LiftingState QName
genFuncName suffix = do
  st <- get
  let newfn = currFunc st ++ '_' : suffix ++ show (currIndex st)
  put st { currIndex = currIndex st + 1 }
  if newfn `elem` topFuncs st
    then genFuncName suffix
    else return (currMod st, newfn)

-- Modify a state by adding a function declaration.
addFun2State :: FuncDecl -> LiftState -> LiftState
addFun2State fd st = st { liftFuncs = fd : liftFuncs st }

------------------------------------------------------------------------------

--- Lift nested cases/lets/free in a FlatCurry program (w.r.t. options).
liftProg :: LiftOptions -> Prog -> Prog
liftProg opts (Prog mn imps types funs ops) =
  let alltopfuns = map (snd . funcName) funs
      initstate  = LiftState opts mn alltopfuns [] "" 0
      transfuns  = evalState (mapM liftTopFun funs) initstate
  in Prog mn imps types (concat transfuns) ops

-- Lift top-level function.
liftTopFun :: FuncDecl -> LiftingState [FuncDecl]
liftTopFun (Func fn ar vis texp rule) = do
  st0 <- get
  put st0 { currFunc = snd fn, currIndex = 0 }
  nrule <- liftRule rule
  st <- get
  put st { liftFuncs = [] }
  return $ Func fn ar vis texp nrule : liftFuncs st

-- Lift newly introduced function.
liftNewFun :: FuncDecl -> LiftingState FuncDecl
liftNewFun (Func fn ar vis texp rule) = do
  nrule <- liftRule rule
  return $ Func fn ar vis texp nrule

liftRule :: Rule -> LiftingState Rule
liftRule (External n)    = return (External n)
liftRule (Rule args rhs) = do
  nrhs <- liftExp False rhs
  return (Rule args nrhs)

-- Lift nested cases/lets/free in expressions.
-- If the second argument is `True`, we are inside an expression where
-- lifting is necessary (e.g., in arguments of function calls).
liftExp :: Bool -> Expr -> LiftingState Expr
liftExp _ (Var v) = return (Var v)
liftExp _ (Lit l) = return (Lit l)
liftExp _ (Comb ct qn es) = do
  nes <- mapM (liftExp True) es
  return (Comb ct qn nes)

liftExp nested exp@(Case ct e brs) = do
  opts <- getOpts
  case e of
    Var _ -> liftCaseExp
    _     -> if liftCArg opts then liftCaseArg else liftCaseExp
 where
  liftCaseExp = do
    if nested -- lift case expression by creating new function
      then do
        cfn <- genFuncName "CASE"
        let vs       = unboundVars exp
            noneType = TCons ("Prelude","None") []
            caseFunc = Func cfn (length vs) Private noneType (Rule vs exp)
        casefun <- liftNewFun caseFunc
        modify (addFun2State casefun)
        return $ Comb FuncCall cfn (map Var vs)
      else do
        ne <- liftExp True e
        nbrs <- mapM liftBranch brs
        return $ Case ct ne nbrs

  liftBranch (Branch pat be) = do
    opts <- getOpts
    ne   <- liftExp (liftCase opts) be
    return (Branch pat ne)

  -- lift case with complex (non-variable) case argument:
  liftCaseArg = do
    ne  <- liftExp True e
    cfn <- genFuncName "COMPLEXCASE"
    let casevar    = maximum (0 : allVars exp) + 1
        vs         = unionMap unboundVarsInBranch brs
        noneType   = TCons ("Prelude","None") []
        caseFunc   = Func cfn (length vs + 1) Private noneType
                          (Rule (vs ++ [casevar]) (Case ct (Var casevar) brs))
    casefun <- liftNewFun caseFunc
    modify (addFun2State casefun)
    return $ Comb FuncCall cfn (map Var vs ++ [ne])

liftExp nested exp@(Let bs e)
 | nested -- lift nested let expressions by creating new function
 = do cfn <- genFuncName "LET"
      let vs       = unboundVars exp
          noneType = TCons ("Prelude","None") []
          letFunc  = Func cfn (length vs) Private noneType (Rule vs exp)
      letfun <- liftNewFun letFunc
      modify (addFun2State letfun)
      return $ Comb FuncCall cfn (map Var vs)
 | otherwise
 = do nes <- mapM (liftExp True) (map snd bs)
      ne <- liftExp True e
      return $ Let (zip (map fst bs) nes) ne

liftExp nested exp@(Free vs e)
 | nested -- lift nested free declarations by creating new function
 = do cfn <- genFuncName "FREE"
      let fvs      = unboundVars exp
          noneType = TCons ("Prelude","None") []
          freeFunc = Func cfn (length fvs) Private noneType (Rule fvs exp)
      freefun <- liftNewFun freeFunc
      modify (addFun2State freefun)
      return $ Comb FuncCall cfn (map Var fvs)
 | otherwise
 = do ne <- liftExp True e
      return (Free vs ne)

liftExp _ (Or e1 e2) = do
  ne1 <- liftExp True e1
  ne2 <- liftExp True e2
  return (Or ne1 ne2)

liftExp nested (Typed e te) = do
  ne <- liftExp nested e
  return (Typed ne te)


--- Find all variables which are not bound in an expression.
unboundVars :: Expr -> [VarIndex]
unboundVars (Var idx)     = [idx]
unboundVars (Lit _)       = []
unboundVars (Comb _ _ es) = unionMap unboundVars es
unboundVars (Or e1 e2)    = union (unboundVars e1) (unboundVars e2)
unboundVars (Typed e _)   = unboundVars e
unboundVars (Free vs e)   = filter (not . flip elem vs) (unboundVars e)
unboundVars (Let bs e) =
  let unbounds = unionMap unboundVars $ e : map snd bs
      bounds   = map fst bs
  in filter (not . flip elem bounds) unbounds
unboundVars (Case _ e bs) =
  union (unboundVars e) (unionMap unboundVarsInBranch bs)

unboundVarsInBranch :: BranchExpr -> [VarIndex]
unboundVarsInBranch (Branch (Pattern _ vs) be) =
  filter (not . flip elem vs) (unboundVars be)
unboundVarsInBranch (Branch (LPattern _) be) = unboundVars be

unionMap :: Eq b => (a -> [b]) -> [a] -> [b]
unionMap f = foldr union [] . map f
