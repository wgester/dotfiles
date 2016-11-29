{-# LANGUAGE DeriveDataTypeable, TypeSynonymInstances,
             MultiParamTypeClasses, ExistentialQuantification,
             FlexibleInstances, FlexibleContexts #-}
module Main where

import           Control.Monad
import           Control.Monad.Trans.Maybe
import           Data.Aeson
import qualified Data.ByteString.Lazy as B
import           Data.List
import qualified Data.Map as M
import qualified Data.MultiMap as MM
import           Data.Maybe
import           Graphics.X11.ExtraTypes.XF86
import           System.Directory
import           System.FilePath.Posix
import           System.Taffybar.Hooks.PagerHints
import           Text.Printf

import           XMonad hiding ( (|||) )
import           XMonad.Actions.CycleWS hiding (nextScreen)
import qualified XMonad.Actions.DynamicWorkspaceOrder as DWO
import           XMonad.Actions.Minimize
import           XMonad.Actions.WindowBringer
import           XMonad.Actions.WindowGo
import           XMonad.Actions.WorkspaceNames
import           XMonad.Config ()
import           XMonad.Hooks.EwmhDesktops
import           XMonad.Hooks.FadeInactive
import           XMonad.Hooks.ManageDocks
import           XMonad.Hooks.Minimize
import           XMonad.Layout.Accordion
import           XMonad.Layout.BoringWindows
import           XMonad.Layout.LayoutCombinators
import           XMonad.Layout.LayoutModifier
import           XMonad.Layout.LimitWindows
import           XMonad.Layout.MagicFocus
import           XMonad.Layout.Minimize
import           XMonad.Layout.MultiColumns
import           XMonad.Layout.MultiToggle
import           XMonad.Layout.MultiToggle.Instances
import           XMonad.Layout.NoBorders
import qualified XMonad.Layout.Renamed as RN
import           XMonad.Layout.Spacing
import qualified XMonad.StackSet as W
import           XMonad.Util.CustomKeys
import qualified XMonad.Util.Dmenu as DM
import qualified XMonad.Util.ExtensibleState as XS
import           XMonad.Util.Minimize
import           XMonad.Util.NamedScratchpad
    (NamedScratchpad(NS), nonFloating, namedScratchpadAction)
import           XMonad.Util.NamedWindows (getName)

myGetWorkspaceNameFromTag getWSName tag =
  printf "%s: %s " tag (fromMaybe "(Empty)" (getWSName tag))

main =
  xmonad $ def
  { modMask = mod4Mask
  , terminal = "urxvt"
  , manageHook = manageDocks <+> myManageHook <+> manageHook def
  , layoutHook = myLayoutHook
  , logHook =
    toggleFadeInactiveLogHook 0.9 +++
    ewmhWorkspaceNamesLogHook' myGetWorkspaceNameFromTag +++
    (myGetWorkspaceNameFromTag <$> getWorkspaceNames' >>= pagerHintsLogHookCustom)
  , handleEventHook =
    docksEventHook <+> fullscreenEventHook +++
    ewmhDesktopsEventHook +++ pagerHintsEventHook +++
    followIfNoMagicFocus +++ minimizeEventHook
  , startupHook = myStartup +++ ewmhWorkspaceNamesLogHook
  , keys = customKeys (const []) addKeys
  }
  where
    x +++ y = mappend y x


-- Utility functions

(<..>) a b = (fmap . fmap) a b

forkM :: Monad m => (i -> m a) -> (i -> m b) -> i -> m (a, b)
forkM a b input = do
  resA <- a input
  resB <- b input
  return (resA, resB)

tee :: Monad m => (i -> m a) -> (i -> m b) -> i -> m a
tee = (fmap . fmap . fmap) (fmap fst) forkM

(>>=/) :: Monad m => m a -> (a -> m b) -> m a
(>>=/) a = (a >>=) . tee return

findM :: (Monad m) => (a -> m (Maybe b)) -> [a] -> m (Maybe b)
findM f = runMaybeT . msum . map (MaybeT . f)

if' :: Bool -> a -> a -> a
if' True  x _ = x
if' False _ y = y

toggleInMap' :: Ord k => Bool -> k -> M.Map k Bool -> M.Map k Bool
toggleInMap' d k m =
  let existingValue = M.findWithDefault d k m
  in M.insert k (not existingValue) m

toggleInMap :: Ord k => k -> M.Map k Bool -> M.Map k Bool
toggleInMap = toggleInMap' True

maybeRemap k = M.findWithDefault k k

(<$.>) :: Functor f => (b -> c) -> (a -> f b) -> a -> f c
(<$.>) l r = fmap l . r

withFocusedD d f = maybe d f <$> (withWindowSet (return . W.peek))

-- Selectors

isHangoutsTitle = isPrefixOf "Google Hangouts"
chromeSelectorBase = className =? "Google-chrome"

chromeSelector = chromeSelectorBase <&&> fmap (not . isHangoutsTitle) title
spotifySelector = className =? "Spotify"
emacsSelector = className =? "Emacs"
transmissionSelector = fmap (isPrefixOf "Transmission") title
hangoutsSelector = chromeSelectorBase <&&> fmap isHangoutsTitle title

virtualClasses = [ (hangoutsSelector, "Hangouts")
                 , (chromeSelector, "Chrome")
                 , (transmissionSelector, "Transmission")
                 ]

-- Commands

hangoutsCommand = "start_hangouts.sh"
spotifyCommand = "spotify"
chromeCommand = "google-chrome-stable"
emacsCommand = "emacsclient -c"
htopCommnad = "urxvt -e htop"
transmissionCommand = "transmission-gtk"

-- Startup hook

myStartup = spawn "systemctl --user start wm.target"

-- Manage hook

myManageHook =
  composeAll . concat $
  [ [transmissionSelector --> doShift "5"]
    -- Hangouts being on a separate workspace freezes chrome
    -- , [ hangoutsSelector --> doShift "2"]
  ]

-- Toggles

unmodifyLayout (ModifiedLayout _ x') =  x'

selectLimit =
  DM.menuArgs "rofi" ["-dmenu", "-i"] ["2", "3", "4"] >>= (setLimit . read)

data MyToggles = LIMIT
               | GAPS
               | MAGICFOCUS
                 deriving (Read, Show, Eq, Typeable)

instance Transformer MyToggles Window where
  transform LIMIT x k = k (limitSlice 2 x) unmodifyLayout
  transform GAPS x k = k (smartSpacing 5 x) unmodifyLayout
  transform MAGICFOCUS x k = k (magicFocus x) unmodifyLayout

myToggles = [LIMIT, GAPS, MAGICFOCUS]
otherToggles = [NBFULL, MIRROR]

followIfNoMagicFocus =
  followOnlyIf $ maybe False not <$> isToggleActive MAGICFOCUS

togglesMap =
  fmap M.fromList $ sequence $
       map toggleTuple myToggles ++ map toggleTuple otherToggles
  where
    toggleTuple toggle =
      fmap (\str -> (str, Toggle toggle)) (toggleToStringWithState toggle)


toggleStateToString s =
  case s of
    Just True -> "ON"
    Just False -> "OFF"
    Nothing -> "N/A"

toggleToStringWithState :: (Transformer t Window, Show t) => t -> X String
toggleToStringWithState toggle =
  (printf "%s (%s)" (show toggle) . toggleStateToString) <$> isToggleActive toggle

selectToggle =
  togglesMap >>= DM.menuMapArgs "rofi" ["-dmenu", "-i"] >>=
             flip whenJust sendMessage

toggleInState :: (Transformer t Window) => t -> Maybe Bool -> X Bool
toggleInState t s = fmap (/= s) (isToggleActive t)

setToggleActive' toggle active =
  toggleInState toggle (Just active) >>=/
  flip when (sendMessage $ Toggle toggle)

-- Ambiguous type reference without signature
setToggleActive :: (Transformer t Window) => t -> Bool -> X ()
setToggleActive = (void .) . setToggleActive'

deactivateFull = setToggleActive NBFULL False

toggleOr toggle toState action =
  setToggleActive' toggle toState >>= ((`when` action) . not)

deactivateFullOr = toggleOr NBFULL False
deactivateFullAnd action = sequence_ [deactivateFull, action]

andDeactivateFull action = sequence_ [action, deactivateFull]

goFullscreen = sendMessage $ Toggle NBFULL

-- Layout setup

rename newName = RN.renamed [RN.Replace newName]

layoutsStart layout = (layout, [Layout layout])
(|||!) (joined, layouts) newLayout =
    (joined ||| newLayout, layouts ++ [Layout newLayout])

layoutInfo =
  layoutsStart (rename "Columns" $ multiCol [1, 1] 2 0.01 (-0.5)) |||!
  rename "Large Main" (Tall 1 (3 / 100) (3 / 4)) |||!
  rename "2 Columns" (Tall 1 (3 / 100) (1 / 2)) |||!
  Accordion

layoutList = snd layoutInfo

layoutNames = [description layout | layout <- layoutList]

selectLayout =
  DM.menuArgs "rofi" ["-dmenu", "-i"] layoutNames >>=
  (sendMessage . JumpToLayout)


myLayoutHook =
  avoidStruts . minimize . boringAuto . mkToggle1 MIRROR . mkToggle1 LIMIT .
  mkToggle1 GAPS . mkToggle1 MAGICFOCUS . mkToggle1 NBFULL . workspaceNamesHook .
  smartBorders . noBorders $ fst layoutInfo

-- WindowBringer

myWindowBringerConfig =
  WindowBringerConfig { menuCommand = "rofi"
                      , menuArgs = ["-dmenu", "-i"]
                      , windowTitler = myDecorateName
                      }

classIfMatches window entry =
  if' <$> runQuery (fst entry) window <*>
      pure (Just $ snd entry) <*>
      pure Nothing

getClassRaw w = fmap resClass $ withDisplay $ io . flip getClassHint w

getVirtualClass = flip findM virtualClasses . classIfMatches

getClass w = fromMaybe <$> getClassRaw w <*> getVirtualClass w

myDecorateName ws w = do
  name <- show <$> getName w
  classTitle <- getClass w
  workspaceToName <- getWorkspaceNames
  return $ printf "%-20s%-40s %+30s" classTitle (take 40 name)
             "in " ++ workspaceToName (W.tag ws)

-- This needs access to X in order to unminimize, which means that I can't be
-- done with the existing window bringer interface
myBringWindow WindowBringerConfig { menuCommand = cmd
                                  , menuArgs = args
                                  , windowTitler = titler } =
  windowMap' titler >>= DM.menuMapArgs cmd args >>= flip whenJust action
  where
    action window =
      sequence_
        [ maximizeWindow window
        , windows $ W.focusWindow window . bringWindow window
        ]

-- Dynamic Workspace Renaming

windowClassFontAwesomeFile =
  fmap (</> ".lib/resources/window_class_to_fontawesome.json") getHomeDirectory

getClassRemap =
  fmap (fromMaybe M.empty . decode) $
       windowClassFontAwesomeFile >>= B.readFile

getClassRemapF = flip maybeRemap <$> getClassRemap
getWSClassNames' w = mapM getClass $ W.integrate' $ W.stack w
getWSClassNames w = io (fmap map getClassRemapF) <*> getWSClassNames' w
currentWSName ws = fromMaybe "" <$> (getWorkspaceNames' <*> pure (W.tag ws))
desiredWSName = (intercalate "|" <$>) . getWSClassNames

setWorkspaceNameToFocusedWindow workspace = do
  currentName <- currentWSName workspace
  newName <- desiredWSName workspace
  when (currentName /= newName) $ setWorkspaceName (W.tag workspace) newName

setWorkspaceNames =
  gets windowset >>= mapM_ setWorkspaceNameToFocusedWindow . W.workspaces

data WorkspaceNamesHook a = WorkspaceNamesHook deriving (Show, Read)

instance LayoutModifier WorkspaceNamesHook Window where
    hook _ = setWorkspaceNames

workspaceNamesHook = ModifiedLayout WorkspaceNamesHook

-- Toggleable fade

newtype ToggleFade a =
  ToggleFade { fadesMap :: M.Map a Bool }
  deriving (Typeable, Read, Show)

instance (Typeable a, Read a, Show a, Ord a) => ExtensionClass (ToggleFade a) where
  initialValue = ToggleFade M.empty
  extensionType = PersistentExtension

fadeEnabledFor query =
  M.findWithDefault True <$> query <*> liftX (fadesMap <$> XS.get)

fadeEnabledForWindow = fadeEnabledFor ask
fadeEnabledForWorkspace = fadeEnabledFor getWindowWorkspace

getWindowWorkspace' = W.findTag <$> ask <*> liftX (withWindowSet return)
getWindowWorkspace = flip fromMaybe <$> getWindowWorkspace' <*> pure "1"

toggleFadeInactiveLogHook =
  fadeOutLogHook .
  fadeIf (isUnfocused <&&> fadeEnabledForWindow <&&> fadeEnabledForWorkspace)

toggleFadingForActiveWindow = withWindowSet $
  maybe (return ()) toggleFadingForWindow . W.peek

toggleFadingForActiveWorkspace =
  withWindowSet $ \ws -> toggleFadingForWindow $ W.currentTag ws

toggleFadingForWindow w =
  fmap (ToggleFade . toggleInMap w . fadesMap) XS.get >>= XS.put

-- Minimize not in class

restoreFocus action =
  withFocused $ \orig -> action >> windows (W.focusWindow orig)

getCurrentWS = W.stack . W.workspace . W.current

withWorkspace f = withWindowSet $ \ws -> maybe (return ()) f (getCurrentWS ws)

minimizeOtherClassesInWorkspace =
    actOnWindowsInWorkspace minimizeWindow windowsWithUnfocusedClass
maximizeSameClassesInWorkspace =
    actOnWindowsInWorkspace maybeUnminimize windowsWithFocusedClass

-- Type annotation is needed to resolve ambiguity
actOnWindowsInWorkspace :: (Window -> X ())
                        -> (W.Stack Window -> X [Window])
                        -> X ()
actOnWindowsInWorkspace windowAction getWindowsAction = restoreFocus $
  withWorkspace (getWindowsAction >=> mapM_ windowAction)

windowsWithUnfocusedClass ws = windowsWithOtherClasses (W.focus ws) ws
windowsWithFocusedClass ws = windowsWithSameClass (W.focus ws) ws
windowsWithOtherClasses = windowsMatchingPredicate (/=)
windowsWithSameClass = windowsMatchingPredicate (==)

windowsMatchingPredicate predicate window workspace =
    windowsSatisfyingPredicate workspace $ do
      windowClass <- getClass window
      return $ predicate windowClass

windowsSatisfyingPredicate workspace getPredicate = do
    predicate <- getPredicate
    filterM (\w -> predicate <$> getClass w) (W.integrate workspace)

windowIsMinimized w = do
  minimized <- XS.gets minimizedStack
  return $ w `elem` minimized

maybeUnminimize w = windowIsMinimized w >>= flip when (maximizeWindow w)

maybeUnminimizeFocused = withFocused maybeUnminimize

maybeUnminimizeAfter = (>> maybeUnminimizeFocused)

maybeUnminimizeClassAfter = (>> maximizeSameClassesInWorkspace)

sameClassOnly action =
  action >> minimizeOtherClassesInWorkspace >> maximizeSameClassesInWorkspace

restoreAllMinimized = restoreFocus $
  withLastMinimized $ \w -> maximizeWindow w >> restoreAllMinimized

restoreOrMinimizeOtherClasses = withLastMinimized' $
  maybe minimizeOtherClassesInWorkspace (`seq` restoreAllMinimized)

getClassPair w = flip (,) w <$> getClass w

windowClassPairs = withWindowSet $ mapM getClassPair . W.allWindows
classToWindowMap = MM.fromList <$> windowClassPairs
allClasses = sort . MM.keys <$> classToWindowMap
thisClass = withWindowSet $ sequence . (getClass <$.> W.peek)

nextClass = do
  classes <- allClasses
  current <- thisClass
  let index = join $ elemIndex <$> current <*> pure classes
  return $ fmap (\i -> cycle classes !! (i + 1)) index

classWindow c = do
  m <- classToWindowMap
  return $ join $ listToMaybe <$> (flip MM.lookup m <$> c)

nextClassWindow = nextClass >>= classWindow

focusNextClass' = join $ windows . maybe id greedyFocusWindow <$> nextClassWindow
focusNextClass = sameClassOnly focusNextClass'

selectClass = join $ DM.menuArgs "rofi" ["-dmenu", "-i"] <$> allClasses

-- Window switching

-- Use greedyView to switch to the correct workspace, and then focus on the
-- appropriate window within that workspace.
greedyFocusWindow w ws =
  W.focusWindow w $
  W.greedyView (fromMaybe (W.currentTag ws) $ W.findTag w ws) ws

shiftThenView i = W.greedyView i . W.shift i

greedyBringWindow w = greedyFocusWindow w . bringWindow w

shiftToEmptyAndView =
  doTo Next EmptyWS DWO.getSortByOrder (windows . shiftThenView)

setFocusedScreen :: ScreenId -> WindowSet -> WindowSet
setFocusedScreen to ws =
  maybe ws (flip setFocusedScreen' ws) $ find ((to ==) . W.screen) (W.visible ws)

setFocusedScreen' to ws @ W.StackSet
  { W.current = prevCurr
  , W.visible = visible
  } = ws { W.current = to
         , W.visible = prevCurr:(deleteBy screenEq to visible)
         }

  where screenEq a b = W.screen a == W.screen b

nextScreen ws @ W.StackSet { W.visible = visible } =
  case visible of
    next:_ -> setFocusedScreen (W.screen next) ws
    _ -> ws

viewOtherScreen ws = W.greedyView ws . nextScreen

shiftThenViewOtherScreen ws w = (viewOtherScreen ws) . (W.shiftWin ws w)

shiftCurrentToWSOnOtherScreen ws s =
  fromMaybe s (flip (shiftThenViewOtherScreen ws) s <$> W.peek s)

shiftToEmptyNextScreen =
  doTo Next EmptyWS DWO.getSortByOrder $ windows . shiftCurrentToWSOnOtherScreen

swapFocusedWith w ws = W.modify' (swapFocusedWith' w) (W.delete' w ws)

swapFocusedWith' w (W.Stack current ls rs) = W.Stack w ls (rs ++ [current])

swapMinimizeStateAfter action =
  withFocused $
  \originalWindow -> do
    _ <- action
    restoreFocus $
      do maybeUnminimizeFocused
         withFocused $
           \newWindow -> when (newWindow /= originalWindow) $ minimizeWindow originalWindow

-- Named Scratchpads

scratchpads = [ NS "htop" htopCommnad (title =? "htop") nonFloating
              , NS "spotify" spotifyCommand spotifySelector nonFloating
              , NS "hangouts" hangoutsCommand  hangoutsSelector nonFloating
              ]

doScratchpad = deactivateFullAnd . namedScratchpadAction scratchpads

-- Raise or spawn

myRaiseNextMaybe =
  ((deactivateFullAnd . maybeUnminimizeClassAfter) .) .
  raiseNextMaybeCustomFocus greedyFocusWindow

myBringNextMaybe =
  ((deactivateFullAnd . maybeUnminimizeAfter) .) .
  raiseNextMaybeCustomFocus greedyBringWindow

bindBringAndRaise :: KeyMask -> KeySym -> X () -> Query Bool -> [((KeyMask, KeySym), X ())]
bindBringAndRaise mask sym start query =
    [ ((mask, sym), doRaiseNext)
    , ((mask .|. controlMask, sym), myBringNextMaybe start query)
    , ((mask .|. shiftMask, sym), doRaiseNext >> minimizeOtherClassesInWorkspace)
    ]
  where doRaiseNext = myRaiseNextMaybe start query

bindBringAndRaiseMany :: [(KeyMask, KeySym, X (), Query Bool)] -> [((KeyMask, KeySym), X())]
bindBringAndRaiseMany = concatMap (\(a, b, c, d) -> bindBringAndRaise a b c d)

-- Screen shift

shiftToNextScreen = withWindowSet $ \ws ->
  case W.visible ws of
    W.Screen i _ _:_ -> windows $ W.view (W.tag i) . W.shift (W.tag i)
    _ -> return ()

-- Key bindings

addKeys conf@XConfig {modMask = modm} =
    [ ((modm, xK_p), spawn "rofi -show drun")
    , ((modm .|. shiftMask, xK_p), spawn "rofi -show run")
    , ((modm, xK_g), andDeactivateFull . maybeUnminimizeAfter $
                   actionMenu myWindowBringerConfig greedyFocusWindow)
    , ((modm .|. shiftMask, xK_g), andDeactivateFull . sameClassOnly $
                   actionMenu myWindowBringerConfig greedyFocusWindow)
    , ((modm, xK_b), andDeactivateFull $ myBringWindow myWindowBringerConfig)
    , ((modm .|. shiftMask, xK_b),
       swapMinimizeStateAfter $ actionMenu myWindowBringerConfig swapFocusedWith)
    , ((modm .|. controlMask, xK_t), spawn
       "systemctl --user restart taffybar.service")
    , ((modm, xK_v), spawn "copyq paste")
    , ((modm, xK_s), swapNextScreen)
    , ((modm .|. controlMask, xK_space), goFullscreen)
    , ((modm, xK_slash), sendMessage $ Toggle MIRROR)
    , ((modm, xK_m), withFocused minimizeWindow)
    , ((modm .|. shiftMask, xK_m), withLastMinimized maximizeWindowAndFocus)
    , ((modm, xK_backslash), toggleWS)
    , ((modm, xK_space), deactivateFullOr $ sendMessage NextLayout)
    , ((modm, xK_z), shiftToNextScreen)
    , ((modm .|. shiftMask, xK_z), shiftToEmptyNextScreen)
    , ((modm, xK_x), windows $ W.shift "NSP")
    , ((modm .|. shiftMask, xK_h), shiftToEmptyAndView)
    -- These need to be rebound to support boringWindows
    , ((modm, xK_j), focusDown)
    , ((modm, xK_k), focusUp)
    , ((modm, xK_m), focusMaster)
    , ((modm, xK_Tab), focusNextClass)

    -- Hyper bindings
    , ((mod3Mask, xK_1), toggleFadingForActiveWindow)
    , ((mod3Mask .|. shiftMask, xK_1), toggleFadingForActiveWorkspace)
    , ((mod3Mask, xK_e), moveTo Next EmptyWS)
    , ((mod3Mask, xK_v), spawn "copyq_rofi.sh")
    , ((mod3Mask, xK_p), spawn "system_password.sh")
    , ((mod3Mask, xK_h), spawn "screenshot.sh")
    , ((mod3Mask, xK_c), spawn "shell_command.sh")
    , ((mod3Mask .|. shiftMask, xK_l), spawn "dm-tool lock")
    , ((mod3Mask, xK_l), selectLayout)
    , ((mod3Mask, xK_k), spawn "rofi_kill_process.sh")
    , ((mod3Mask, xK_t), selectToggle)
    , ((mod3Mask, xK_r), spawn "rofi_restart_service.sh")

    -- ModAlt bindings
    , ((modalt, xK_w), spawn "rofi_wallpaper.sh")
    , ((modalt, xK_z), spawn "split_out_chrome_tab.sh")
    , ((modalt, xK_space), deactivateFullOr restoreOrMinimizeOtherClasses)
    , ((modalt, xK_Return), deactivateFullAnd restoreAllMinimized)
    , ((modalt, xK_4), selectLimit)

    -- ScratchPads
    , ((modalt, xK_m), doScratchpad "htop")
    , ((modalt .|. controlMask, xK_s), doScratchpad "spotify")
    , ((modalt .|. controlMask, xK_h), doScratchpad "hangouts")

    , ((modalt, xK_h),
       myRaiseNextMaybe (spawn hangoutsCommand) hangoutsSelector)
    , ((modalt, xK_s),
       myRaiseNextMaybe (spawn spotifyCommand) spotifySelector)

    -- playerctl
    , ((mod3Mask, xK_f), spawn "playerctl play-pause")
    , ((0, xF86XK_AudioPause), spawn "playerctl play-pause")
    , ((0, xF86XK_AudioPlay), spawn "playerctl play-pause")
    , ((mod3Mask, xK_d), spawn "playerctl next")
    , ((0, xF86XK_AudioNext), spawn "playerctl next")
    , ((mod3Mask, xK_a), spawn "playerctl previous")
    , ((0, xF86XK_AudioPrev), spawn "playerctl previous")

    -- volume control
    , ((0, xF86XK_AudioRaiseVolume), spawn "pulseaudio-ctl up")
    , ((0, xF86XK_AudioLowerVolume), spawn "pulseaudio-ctl down")
    , ((0, xF86XK_AudioMute), spawn "pulseaudio-ctl mute")
    , ((mod3Mask, xK_w), spawn "pulseaudio-ctl up")
    , ((mod3Mask, xK_s), spawn "pulseaudio-ctl down")

    ] ++ bindBringAndRaiseMany

    [ (modalt, xK_e, spawn emacsCommand, emacsSelector)
    , (modalt, xK_c, spawn chromeCommand, chromeSelector)
    -- , (modalt, xK_s, spawn spotifyCommand, spotifySelector)
    -- , (modalt, xK_h, spawn hangoutsCommand, hangoutsSelector)
    , (modalt, xK_t, spawn transmissionCommand, transmissionSelector)
    ] ++
    -- Replace original moving stuff around + greedy view bindings
    [((additionalMask .|. modm, key), windows $ function workspace)
         | (workspace, key) <- zip (workspaces conf) [xK_1 .. xK_9]
         , (function, additionalMask) <-
             [ (W.greedyView, 0)
             , (W.shift, shiftMask)
             , (shiftThenView, controlMask)]]
    where
      modalt = modm .|. mod1Mask

-- Local Variables:
-- flycheck-ghc-args: ("-Wno-missing-signatures")
-- haskell-indent-offset: 2
-- End:
