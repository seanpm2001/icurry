------------------------------------------------------------------------------
--- This module contains a simple compiler from FlatCurry to ICurry programs.
---
--- @author Michael Hanus
--- @version January 2020
------------------------------------------------------------------------------

module ICurry.Main where

import GetOpt
import ReadNumeric       ( readNat )
import System            ( exitWith, getArgs )

import System.CurryPath  ( stripCurrySuffix )

import ICurry.Compiler
import ICurry.Files
import ICurry.Interpreter
import ICurry.Types

------------------------------------------------------------------------------
banner :: String
banner = unlines [bannerLine,bannerText,bannerLine]
 where
   bannerText = "ICurry Compiler (Version of 23/01/20)"
   bannerLine = take (length bannerText) (repeat '=')

main :: IO ()
main = do
  args <- getArgs
  (opts,progs) <- processOptions args
  case progs of
    []  -> error "Module name missing"
    [p] -> mainProg opts p
    _   -> error "Too many module names provided"

mainProg :: ICOptions -> String -> IO ()
mainProg opts p = do
  iprog <- icCompile opts p
  let imain = optMain opts
  if null imain
    then do
      writeICurryFile (iCurryFileName p) iprog
      printStatus opts $
        "ICurry program written to '" ++ iCurryFileName p ++ "'"
    else do
      printStatus opts $ "Executing main function '" ++ imain ++ "'..."
      let opts1 = if optShowGraph opts
                    then defOpts { withGraph = True, waitTime = 1
                                 , withViewer = optViewPDF opts }
                    else defOpts
          opts2 = if optInteractive opts
                    then opts1 { interactive = True, verbosity = 2 }
                    else opts1
      execIProg opts2 iprog imain

--- Process the actual command line argument and return the options
--- and the name of the main program.
processOptions :: [String] -> IO (ICOptions,[String])
processOptions argv = do
  let (funopts, args, opterrors) = getOpt Permute options argv
      opts = foldl (flip id) defaultICOptions funopts
  unless (null opterrors)
         (putStr (unlines opterrors) >> printUsage >> exitWith 1)
  when (optHelp opts) (printUsage >> exitWith 0)
  return (opts, map stripCurrySuffix args)
 where
  printUsage = putStrLn (banner ++ "\n" ++ usageText)

-- Help text
usageText :: String
usageText =
  usageInfo ("Usage: icurry [options] <module name>\n") options

-- Definition of actual command line options.
options :: [OptDescr (ICOptions -> ICOptions)]
options =
  [ Option "h?" ["help"]
           (NoArg (\opts -> opts { optHelp = True }))
           "print help and exit"
  , Option "q" ["quiet"]
           (NoArg (\opts -> opts { optVerb = 0 }))
           "run quietly (no output, only exit code)"
  , Option "v" ["verbosity"]
            (OptArg (maybe (checkVerb 2) (safeReadNat checkVerb)) "<n>")
            "verbosity level:\n0: quiet (same as `-q')\n1: show status messages (default)\n2: show generated program (same as `-v')\n3: show all details"
  , Option "m" ["main"]
           (ReqArg (\s opts -> opts { optMain = s }) "<f>")
           "name of the main function to be interpreted\n(otherwise the ICurry program is stored)"
  , Option "g" ["graph"]
           (NoArg (\opts -> opts { optShowGraph = True }))
           "show the term graph during execution\n(requires 'dot' and 'evince')"
  , Option "" ["viewer"]
           (ReqArg (\s opts -> opts { optViewPDF = s }) "<c>")
           "command to view PDF files (default: 'evince')"
  , Option "i" ["interactive"]
           (NoArg (\opts -> opts { optInteractive = True }))
           "interactive execution (wait after each step)"
  ]
 where
  safeReadNat opttrans s opts =
   let numError = error "Illegal number argument (try `-h' for help)"
   in maybe numError
            (\ (n,rs) -> if null rs then opttrans n opts else numError)
            (readNat s)

  checkVerb n opts = if n>=0 && n<4
                     then opts { optVerb = n }
                     else error "Illegal verbosity level (try `-h' for help)"

------------------------------------------------------------------------------
