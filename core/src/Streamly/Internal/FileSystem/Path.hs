-- |
-- Module      : Streamly.Internal.FileSystem.Path
-- Copyright   : (c) 2023 Composewell Technologies
-- License     : BSD3
-- Maintainer  : streamly@composewell.com
-- Portability : GHC
--
-- = User Notes
--
-- Well typed, flexible, extensible and efficient file systems paths,
-- preserving the OS and filesystem encoding.
--
-- /Flexible/: you can choose the level of type safety you want. 'Path' is the
-- basic path type which can represent a file, directory, absolute or relative
-- path with no restrictions. Depending on how much type safety you want, you
-- can choose appropriate type wrappers or a combination of those to wrap the
-- 'Path' type.
--
-- The basic type-safety is provided by the
-- "Streamly.Internal.FileSystem.PosixPath.LocSeg" module. We make a distinction
-- between two types of paths viz. locations and segments. Locations are
-- represented by the @Loc Path@ type and path segments are represented by the
-- @Seg Path@ type. Locations are paths pointing to specific objects in the
-- file system absolute or relative e.g. @\/usr\/bin@, @.\/local\/bin@, or @.@.
-- Segments are a sequence of path components without any reference to a
-- location e.g. @usr\/bin@, @local\/bin@, or @../bin@ are segments. This
-- distinction is for safe append operation on paths, you can only append
-- segments to any path and not a location. If you use the 'Path' type then
-- append can fail if you try to append a location to a path, but if you use
-- @Loc Path@ or @Seg Path@ types then append can never fail.
--
-- Independently of the location or segment distinction you can also make the
-- distinction between files and directories using the
-- "Streamly.Internal.FileSystem.PosixPath.FileDir" module. @File Path@ type
-- represents a file whereas @Dir Path@ represents a directory. It provides
-- safety against appending a path to a file. Append operation allows appending
-- to only 'Dir' types.
--
-- You can use the 'Loc', 'Seg' or 'Dir', 'File' types independent of each
-- other by using only the required module. If you want both types of
-- distinctions then you can use them together as well using the
-- "Streamly.Internal.FileSystem.PosixPath.Typed" module.  For example, the
-- @Loc (Dir Path)@ represents a location which is a directory. You can only
-- append to a path that has 'Dir' in it and you can only append a 'Seg' type.
--
-- You can choose to use just the basic 'Path' type or any combination of safer
-- types. You can upgrade or downgrade the safety using the @adapt@ operation.
-- Whenever a less restrictive path type is converted to a more restrictive
-- path type, the conversion involves run-time checks and it may fail. However,
-- a more restrictive path type can be freely converted to a less restrictive
-- one.
--
-- Extensible, you can define your own newtype wrappers similar to 'File' or
-- 'Dir' to provide custom restrictions if you want.
--
-- Any path type can be converted to the 'FilePath' type using the 'toString'
-- operation. Operations to convert to and from 'OsPath' type at zero cost are
-- provided in the @streamly-filepath@ package. The types use the same
-- underlying representation as the 'OsPath' type.
--
-- = Developer Notes:
--
-- We should be able to manipulate windows paths on posix and posix paths on
-- windows as well. Therefore, we have WindowsPath and PosixPath types which
-- are supported on both platforms. However, the Path module aliases Path to
-- WindowsPath on Windows and PosixPath on Posix.
--
-- Conventions: A trailing separator on a path indicates that it is a
-- directory. However, the absence of a trailing separator does not convey any
-- information, it could either be a directory or a file.
--
-- You may also find the 'str' quasiquoter from "Streamly.Unicode.String" to be
-- useful in creating paths.
--
--  * https://en.wikipedia.org/wiki/Path_(computing)
--  * https://learn.microsoft.com/en-us/windows/win32/fileio/naming-a-file
--  * https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-dtyp/62e862f4-2a51-452e-8eeb-dc4ff5ee33cc
--
-- == File System Tree
--
-- A file system is a tree when there are no hard links or symbolic links. But
-- in the presence of symlinks it could be a DAG or a graph, because directory
-- symlinks can create cycles.
--
-- == Location and Segments
--
-- We make two distinctions for paths, a path could refer to a location or it
-- could refer to a segment or segments.
--
-- A path that refers to a particular object in the file system  is called a
-- location e.g. /usr is a location, . is a location, ./bin is a location. A
-- location could be absolute e.g. /usr or it could be relative e.g. ./bin . A
-- location always has two components, a specific "root" which could be
-- explicit or implicit, and a path segment relative to the root. A location
-- with a fixed root is known as an absolute location whereas a location with
-- an implicit root e.g. "./bin" is known as a relative location.
--
-- A path that does not refer to a particular location but defines steps to go
-- from some place to another is a path segment. For example, "local/bin" is a
-- path segment whereas "./local/bin" is a location.
--
-- Locations can never be appended to another location or to a path segment
-- whereas a segment can be appended.
--
-- == Comparing Paths
--
-- We can compare two absolute locations or path segments but we cannot compare
-- two relative locations. If each component of the path is the same then the
-- paths are considered to be equal.
--
-- == Implicit Roots (.)
--
-- On Posix and Windows "." implicitly refers to the current directory. On
-- Windows a path like @/Users/@ has the drive reference implicit. Such
-- references are contextual and may have different meanings at different
-- times.
--
-- @./bin@ may refer to a different location depending on what "." is
-- referring to. Thus we should not allow @./bin@ to be appended to another
-- path, @bin@ can be appended though. Similarly, we cannot compare @./bin@
-- with @./bin@ and say that they are equal because they may be referring to
-- different locations depending on in what context the paths were created.
--
-- The same arguments apply to paths with implicit drive on Windows.
--
-- We can treat @.\/bin\/ls@ as an absolute path with "." as an implicit root.
-- The relative path is "bin/ls" which represents steps from somewhere to
-- somewhere else rather than a particular location. We can also call @./bin@
-- as a "located path" as it points to particular location rather than "steps"
-- from one place to another. If we want to append such paths we need to first
-- make them explicitly relative by dropping the implicit root. Or we can use
-- unsafeAppend to force it anyway or unsafeCast to convert absolute to
-- relative.
--
-- On these absolute (located/Loc) paths if we use takeRoot, it should return
-- RootCurDir, RootCurDrive and @Root Path@ to distinguish @./@, @/@, @C:/@. We
-- could represent them by different types but that would make the types even more
-- complicated. So runtime checks are are a good balance.
--
-- Path comparison should return EqTrue, EqFalse or EqUnknown. If we compare
-- these absolute/located paths having implicit roots then result should be
-- EqUnknown or maybe we can just return False?. @./bin@ and @./bin@ should be
-- treated as paths with different roots/drives but same relative path. The
-- programmer can explicitly drop the root and compare the relative paths if
-- they want to check literal equality.
--
-- Note that a trailing . or a . in the middle of a path is different as it
-- refers to a known name.
--
-- == Ambiguous References (..)
--
-- ".." in a path refers to the parent directory relative to the current path.
-- For an absolute root directory ".." refers to the root itself because you
-- cannot go further up.
--
-- When resolving ".." it always resolves to the parent of a directory as
-- stored in the directory entry. So if we landed in a directory via a symlink,
-- ".." can take us back to a different directory and not to the symlink
-- itself. Thus @a\/b/..@ may not be the same as @a/@. Shells like bash keep
-- track of the old paths explicitly, so you may not see this behavior when
-- using a shell.
--
-- For this reason we cannot process ".." in the path statically. However, if
-- the components of two paths are exactly the same then they will always
-- resolve to the same target. But two paths with different components could
-- also point to the same target. So if there are ".." in the path we cannot
-- definitively say if they are the same without resolving them.
--
-- == Exception Handling
--
-- Path creation routines use MonadThrow which can be interpreted as an Either
-- type. It is rare to actually handle exceptions in path creation functions,
-- we would rather fix the issue, so partial functions should also be fine. But
-- there may be some cases where we are parsing paths from external inputs,
-- reading from a file etc where we may want to handle exceptions. We can
-- always create partial wrappers from these if that is convenient to use.
--

#if defined(mingw32_HOST_OS) || defined(__MINGW32__)
#define OS_PATH WindowsPath
#else
#define OS_PATH PosixPath
#endif

module Streamly.Internal.FileSystem.Path
    (
      Path
    , module Streamly.Internal.FileSystem.OS_PATH
    )
where

import Streamly.Internal.FileSystem.OS_PATH

type Path = OS_PATH
