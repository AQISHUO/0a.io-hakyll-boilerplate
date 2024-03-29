--------------------------------------------------------------------------------
{-# LANGUAGE OverloadedStrings #-}
import           Data.Monoid (mappend)
import           Hakyll
import System.Directory
import Data.List.Split
import System.IO
import Control.Monad
import Data.List
import qualified Data.Text as T
import Text.Regex
import           Text.Pandoc.Options
import           Network.URI                     (escapeURIString, isUnescapedInURI)
import           System.FilePath               (takeBaseName, takeExtension)

pandocOptions = defaultHakyllWriterOptions{ writerHTMLMathMethod = MathJax "" }


makeNewContext :: String -> String -> (String -> String) -> Context String
makeNewContext original new stringTrans  = field new $ \item -> do
    val <- getMetadataField (itemIdentifier item) original
    case val of
        Nothing -> return mempty
        Just val_ -> return (stringTrans val_)

imgEscURLCtx = makeNewContext "coverPainting" "imgEscURL" (escapeURIString isUnescapedInURI)

paintingInfo = makeNewContext "coverPainting" "paintingUrl" (\a -> paintingUrl (extractPaintingInfo "title" a) (extractPaintingInfo "author" a))
    `mappend` makeNewContext "coverPainting" "paintingArtistName" (extractPaintingInfo "author")
    `mappend` makeNewContext "coverPainting" "paintingTitle" (extractPaintingInfo "title")
    `mappend` makeNewContext "coverPainting" "paintingYear" (extractPaintingInfo "year")

------------------------------------------------------------------------------
timedWithEspImgCtx :: Context String
timedWithEspImgCtx =
    imgEscURLCtx `mappend`
    dateField "date" "%B %e %Y" `mappend`
    defaultContext

--------------------------------------------------------------------------------
compressScssCompiler :: Compiler (Item String)
compressScssCompiler = do
  fmap (fmap compressCss) $
    getResourceString
    >>= withItemBody (unixFilter "sass" [ "-s"
                                        , "--scss"
                                        , "--style", "compressed"
                                        , "--load-path", "css"
                                        ])
--------------------------------------------------------------------------------
teaserFieldWithSeparatorNoHTML separator key snapshot = field key $ \item -> do
    body <- itemBody <$> loadSnapshot (itemIdentifier item) snapshot
    case needlePrefix separator body of
        Nothing -> fail $
            "Hakyll.Web.Template.Context: no teaser defined for " ++
            show (itemIdentifier item)
        Just t -> return (stripTags t)

teaserFieldNOHTEML = teaserFieldWithSeparatorNoHTML "<!--more-->"
---------------

allPosts = ("posts/video/*" .||. "posts/*")



main :: IO ()
main = do
    updateArtworkInfo
    updateMusicDir
    musicInnerDirs <- listDirectory "music-for-work"
    hakyll $ do
        match ("archy.asc" .||. "吖奇.txt" .||. "mail.txt" .||. "img/*" .||. "img/*/*" .||. "fonts/*" .||. "js/*") $ do
          route   idRoute
          compile copyFileCompiler
        match ("GET-REKTED.txt") $ do
            route   $ setExtension "html"
            compile  copyFileCompiler
        match "css/*.css" $ do
            route   idRoute
            compile compressCssCompiler
        match "css/*.scss" $ do
            route   $ setExtension "css"
            compile compressScssCompiler
        match allPosts $ do
            route $ setExtension "html"
                `composeRoutes` gsubRoute "(posts/|[0-9]+-[0-9]+-[0-9]+-|featured/|more/)" (const "")
            compile $ pandocCompilerWith defaultHakyllReaderOptions pandocOptions
                >>= saveSnapshot "content"
                >>= loadAndApplyTemplate "templates/post.html"  (paintingInfo `mappend` timedWithEspImgCtx)
                >>= loadAndApplyTemplate "templates/default.html" ( (teaserFieldNOHTEML "teaser" "content") `mappend` timedWithEspImgCtx)
                >>= relativizeUrls

        match "posts/other/*" $ do
            compile $ pandocCompiler
                >>= loadAndApplyTemplate "templates/simple-archy-item.html" timedWithEspImgCtx
                >>= loadAndApplyTemplate "templates/page-session.html" timedWithEspImgCtx
                >>= relativizeUrls

        match ("music-for-work/*/*" .||. "artwork-info/*") $ do
            compile $ pandocCompiler
                >>= relativizeUrls

        createRowOf3Session "2000-01-01-row0.html" "posts/video/*" "TITLE" "subtitle" "1001"
        createRowOf3Session "2000-01-01-row1.html" "posts/video/*" "TITLE" "subtitle" "1001"


        create ["index.html"] $ page "home" "isBlog" "PAGETITLE" ["2000-01-01-row0.html","2000-01-01-row1.html"]
        create ["page1.html"] $ page "home" "" "PAGETITLE" ["2000-01-01-row0.html"]

        createPageOfSessionsBasedOnDirectoryStructure "home" "isMusicForWork" "music-for-work" "Music For Work" musicInnerDirs
        create ["about.html"] $ page "home-sub" "" "About me" [ "posts/other/about0.md"]
        create ["about-0a.html"] $ page "home-sub" "isPhoneAbout" "About 0a.io" [ "posts/other/about0.md"]

        match "templates/*" $ compile templateBodyCompiler

        match ( "links/*" .||. "links/*/*" .||. "links/*/*/*" ) $ do
            route $  (gsubRoute "links/" (const ""))
            compile $ copyFileCompiler

        -- create ["sitemap.xml"] $ do
        --        route   idRoute
        --        compile $ do
        --          c1 <- recentFirst =<< loadAll "posts/chapter1/*/*"
        --          c15 <- recentFirst =<< loadAll "posts/chapter1.5/*"
        --          c2 <- recentFirst =<< loadAll "posts/chapter2/*"
        --          old <- recentFirst =<< loadAll "posts/old-blog/*"
        --          film <- recentFirst =<< loadAll "posts/pretentious-reviews/film/*"
        --          pages <- loadAll "*.html"
        --          let everything = (return (pages ++ c1 ++ c15 ++ c2 ++ old ++ film))
        --          let sitemapCtx = mconcat
        --                           [ listField "entries" defaultContext everything
        --                           , defaultContext
        --                           ]
        --          makeItem ""
        --           >>= loadAndApplyTemplate "templates/sitemap.xml" sitemapCtx

        create ["atom.xml"] $ do
              route idRoute
              compile $ do
                  let feedCtx = (paintingInfo `mappend` timedWithEspImgCtx) `mappend` bodyField "description"
                  posts <- fmap (take 10) . recentFirst =<<
                      loadAllSnapshots allPosts "content"
                  renderAtom myFeedConfiguration feedCtx posts
        create ["rss.xml", "feed.xml"] $ do
              route idRoute
              compile $ do
                  let feedCtx = (paintingInfo `mappend` timedWithEspImgCtx) `mappend` bodyField "description"
                  posts <- fmap (take 10) . recentFirst =<<
                      loadAllSnapshots allPosts "content"
                  renderRss myFeedConfiguration feedCtx posts



-----

createRowOf3SessionWithoutTimeCtx = createRowOf3Session_ defaultContext return

createRowOf3Session = createRowOf3Session_ timedWithEspImgCtx recentFirst

createRowOf3Session_ ctx postPossessing identifer filePath maintitle subtitle width = create [identifer] $ do
  compile $ do
      posts <- postPossessing =<< loadAll filePath
      let archiveCtx =
              rowsOf3 posts "row" ctx `mappend`
              constField "maintitle" maintitle `mappend`
              constField "subtitle" subtitle `mappend`
              constField "width" width `mappend`
              ctx
      makeItem ""
          >>= loadAndApplyTemplate "templates/rows-of-three.html" archiveCtx
          >>= loadAndApplyTemplate "templates/page-session.html" archiveCtx
          >>= relativizeUrls

-----

createPageOfSessionsBasedOnDirectoryStructure pageType isX dirPath title innerDirs= do
    let createSessionByDir subdir = createRowOf3Session (fromFilePath (subdir++".html")) (fromGlob (dirPath++"/"++subdir++"/*")) (drop 11 subdir) "" "900"
    mapM_ createSessionByDir innerDirs
    create [fromFilePath (dirPath ++ ".html")] $ page pageType isX title [subdir++".html" | subdir <- innerDirs]

------
page = page_ (\a -> return)
page_ moreTemplating pageType isX title sessions = do
  route idRoute
  compile $ do
      sessions <- recentFirst =<< loadAll (fromList $ [fromFilePath s | s <- sessions])
      let indexCtx =
              listField "sessions" timedWithEspImgCtx (return sessions) `mappend`
              constField isX "true" `mappend`
              constField "title" title `mappend`
              constField "pageType" pageType `mappend`
              defaultContext
      makeItem ""
          >>= applyAsTemplate indexCtx
          >>= loadAndApplyTemplate "templates/session-loop.html" indexCtx
          >>= loadAndApplyTemplate (fromFilePath ("templates/"++pageType++".html")) indexCtx
          >>= moreTemplating indexCtx
          >>= loadAndApplyTemplate "templates/default.html" indexCtx
          >>= relativizeUrls

---------

rowsOf3od :: Int -> [a] -> ([a],[a],[a]) -> ([a],[a],[a])
rowsOf3od 0 (x:xs) (r0,r1,r2) = rowsOf3od 1 xs (x:r0,r1,r2)
rowsOf3od 1 (x:xs) (r0,r1,r2) = rowsOf3od 2 xs (r0,x:r1,r2)
rowsOf3od 2 (x:xs) (r0,r1,r2) = rowsOf3od 0 xs (r0,r1,x:r2)
rowsOf3od _ [] (r0,r1,r2)         = (reverse r0, reverse r1, reverse r2)

rowsOf3 list identifier ctx = foldl mappend defaultContext contexts
  where
    contexts = [listField (identifier ++ show num) ctx (return items) | (items,num) <- [(r0,0),(r1,1),(r2,2)]] ++
        [listField "everything" ctx (return list)]
    (r0,r1,r2) = rowsOf3od 0 list ([],[],[])

---------
makeArtworkYaml (title:year:author:paintingURL:[]) = "---\n" ++
    "title: \"" ++ title ++ "\"\n" ++
    "year: \"" ++ year ++ "\"\n" ++
    "subtitle: \"" ++ author ++ "\"\n" ++
    "displayImg: \"" ++ paintingURL ++ "\"\n" ++
    "isArtworkInfo: 1\n" ++
    "url: \""++(paintingUrl title author) ++ "\"\n" ++
    "newTab: 1\n" ++
    "---"
makeArtworkYaml wrongformat = show wrongformat

extractPaintingInfo infoType str = formattingImgStr $ extractPainting_ infoType $ splitOn ", " str
extractPainting_ "author" (title:year:author:[]) = author
extractPainting_ "title"(title:year:author:[]) = title
extractPainting_ "year" (title:year:author:[]) = year
extractPainting_ _ _ = "something went wrong"

makeMusicYaml (title:artist:link:imgURL:virtualDate:[]) = "---\n" ++
    "title: \"" ++ title ++ "\"\n" ++
    "subtitle: \"" ++ artist ++ "\"\n" ++
    "customForwardUrl: \"" ++ link ++ "\"\n" ++
    "displayImg: \"" ++ imgURL ++ "\"\n" ++
    "date: \"" ++ virtualDate ++ "\"\n" ++
    "newTab: true \n" ++
    -- "imageWidth: \"640px\" \n" ++
    -- "imageHeight: \"480px\" \n" ++
    -- "lazyload: true \n" ++
    "---"
makeMusicYaml wrongformat = show wrongformat

updateArtworkInfo = do
    empty "artwork-info"
    files <- listDirectory "img/covers"
    let paintings = map (\a -> take (length a - 4) a) $ filter (\a -> isSuffixOf ".jpg" a) files
    let paintingData = [ (splitOn ", " dataString) ++ ["img/covers/" ++ dataString ++ ".jpg"] | dataString <- paintings ]
    propagate "artwork-info" paintingData makeArtworkYaml


updateMusicDir = do
    putStr "Updating music dir\n"
    empty "music-for-work"
    txt <- readFile "music-for-work.archy"
    let linesOfTxt = lines txt
    let metaData = splitOn ", " (linesOfTxt !! 0)
    putStr ("With metadata\n" ++ show metaData ++ "\n")
    let dirs = map (\(datum,num) -> "music-for-work/"++(virtualDateForOrdering num) ++ "-" ++ datum) (zipWidthIndex metaData)
    mapM_ createDirectory dirs
    putStr ("Creating directorires\n" ++ show dirs ++ "\n")
    let getYoutubeThumbnail (Just (vidId:_)) = "https://img.youtube.com/vi/"++vidId++"/0.jpg"
    let getYoutubeId link = matchRegex (mkRegex "watch\\?v=([^&]+)") link
    let musicDataFormating (musicData@(title:artist:link:[]),nth) = musicDataFormating $ (musicData ++ [(getYoutubeThumbnail $ getYoutubeId link)], nth)
        musicDataFormating (musicData,nth) = musicData ++ [virtualDateForOrdering nth]
    let musicData = [ map musicDataFormating $ zipWidthIndex [splitOn ", " singleItemDataString  | singleItemDataString <- musicGenreList] | musicGenreList <- splitOn [""] (tail $ tail linesOfTxt)]
    mapM_ (\(dir,dataStrings) -> propagate dir dataStrings makeMusicYaml) $ zip dirs musicData

zipWidthIndex :: [a] -> [(a,Int)]
zipWidthIndex list = (zip list $ reverse [0..(length list)])

------------------

formattingImgStr str = T.unpack $ foldl (\str (x,y) -> T.replace (T.pack x) (T.pack y) str) (T.pack str) [("_perc", "%"),("_comma",","),("_hash","#"),("Rene","René"),("Aquel","Aquél"), ("Compenetracao estatica interior de uma cabeca complementarismo congenito absoluto","Compenetração estática interior de uma cabeça = complementarismo congénito absoluto (SENSIBILIDADE LITHOGRAPHICA)")]
propagate folder dataLists dataToFile = do
    let formated = map (\dataList -> ((map formattingImgStr) . init) dataList ++ [last dataList]) dataLists
    zipWithM_ writeFile (map ((\a -> folder ++ "/" ++ a ++ ".md") . head) formated) (map dataToFile formated)

------------------
virtualDateForOrdering n = "2018-01-" ++ (date (n + 1))
    where date m = if m < 10
            then "0"++(show m) else (show m)
--------

empty dir = do
    removePathForcibly dir
    createDirectory dir
    putStr ("Emptying directory " ++ dir ++"\n")

paintingUrl = purl

myFeedConfiguration :: FeedConfiguration
myFeedConfiguration = FeedConfiguration
    { feedTitle       = "0a.io"
    , feedDescription = "latest on 0a.io"
    , feedAuthorName  = "Archy Will He"
    , feedAuthorEmail = "a@0a.io"
    , feedRoot        = "https://0a.io"
    }

purl :: String -> String -> String
purl _ "Mary Pratt" = "http://thechronicleherald.ca/heraldmagazine/1254755-the-life-and-art-of-painter-mary-pratt"
purl _ "Paolo Scheggi" = "https://www.robilantvoena.com/usr/documents/press/download_url/95/the-art-newspaper-the-rise-of-paolo-scheggi-17-june-2015.pdf"
purl _ "Ludwig Wilding" = "http://www.arasgallery.com/profile.php?id=49"
purl _ "Francois Morellet" = "https://en.wikipedia.org/wiki/Fran%C3%A7ois_Morellet"
purl _ "Jacek Yerka" = "http://www.yerkaland.com/language/en/"
purl _ "Laszlo Mednyanszky" = "https://en.wikipedia.org/wiki/L%C3%A1szl%C3%B3_Medny%C3%A1nszky"
purl "Aquél que camina delante" _  = "https://wsimag.com/art/22210-aquel-que-camina-delante"
purl _ "Analia Saban" = "http://www.analiasabanstudio.com/index.html"
purl "Flame Nebula" _ = "http://chandra.harvard.edu/photo/2014/flame/"
purl title author  = "https://www.wikiart.org/en/Search/"++title++"%20"++author
purl title "René Magritte"  = "https://www.wikiart.org/en/Search/"++title++"%20Rene Magritte"
