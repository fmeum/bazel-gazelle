/* Copyright 2016 The Bazel Authors. All rights reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

// Package label provides utilities for parsing and manipulating
// Bazel labels. See
// https://docs.bazel.build/versions/master/build-ref.html#labels
// for more information.
package label

import (
	"errors"
	"fmt"
	"log"
	"path"
	"regexp"
	"strings"
	"unicode"

	"github.com/bazelbuild/bazel-gazelle/pathtools"
)

// A Label represents a label of a build target in Bazel. Labels have three
// parts: a repository name, a package name, and a target name, formatted
// as @repo//pkg:target.
type Label struct {
	// Repo is the repository name. If omitted, the label refers to a target
	// in the current repository.
	Repo string

	// Pkg is the package name, which is usually the directory that contains
	// the target. If both Repo and Pkg are omitted, the label is relative.
	Pkg string

	// Name is the name of the target the label refers to. Name must not be empty.
	// Note that the name may be omitted from a label string if it is equal to
	// the last component of the package name ("//x" is equivalent to "//x:x"),
	// but in either case, Name should be set here.
	Name string

	// Relative indicates whether the label refers to a target in the current
	// package. Relative is true if and only if Repo and Pkg are both omitted.
	Relative bool
}

// New constructs a new label from components.
func New(repo, pkg, name string) Label {
	return Label{Repo: repo, Pkg: pkg, Name: name}
}

// NoLabel is the zero value of Label. It is not a valid label and may be
// returned when an error occurs.
var NoLabel = Label{}

var (
	labelRepoRegexp = regexp.MustCompile(`^@$|^[A-Za-z.-][A-Za-z0-9_.-]*$`)
	labelPkgRegexp  = regexp.MustCompile(`^[A-Za-z0-9/._@-]*$`)
	// This was taken from https://docs.bazel.build/versions/main/build-ref.html#name
	labelNameRegexp = regexp.MustCompile("^[A-Za-z0-9!%-@^_` \"#$&'()*-+,;<=>?\\[\\]{|}~/.]*$")
)

// Parse reads a label from a string.
// See https://docs.bazel.build/versions/master/build-ref.html#lexi.
func Parse(s string) (Label, error) {
	origStr := s

	relative := true
	var repo string
	if strings.HasPrefix(s, "@") {
		relative = false
		endRepo := strings.Index(s, "//")
		if endRepo > len("@") {
			repo = s[len("@"):endRepo]
			s = s[endRepo:]
			// If the label begins with "@//...", set repo = "@"
			// to remain distinct from "//...", where repo = ""
		} else if endRepo == len("@") {
			repo = s[:len("@")]
			s = s[len("@"):]
		} else {
			repo = s[len("@"):]
			s = "//:" + repo
		}
		if !labelRepoRegexp.MatchString(repo) {
			return NoLabel, fmt.Errorf("label parse error: repository has invalid characters: %q", origStr)
		}
	}

	var pkg string
	if strings.HasPrefix(s, "//") {
		relative = false
		endPkg := strings.Index(s, ":")
		if endPkg < 0 {
			pkg = s[len("//"):]
			s = ""
		} else {
			pkg = s[len("//"):endPkg]
			s = s[endPkg:]
		}
		if !labelPkgRegexp.MatchString(pkg) {
			return NoLabel, fmt.Errorf("label parse error: package has invalid characters: %q", origStr)
		}
	}

	if s == ":" {
		return NoLabel, fmt.Errorf("label parse error: empty name: %q", origStr)
	}
	name := strings.TrimPrefix(s, ":")
	if !labelNameRegexp.MatchString(name) {
		return NoLabel, fmt.Errorf("label parse error: name has invalid characters: %q", origStr)
	}

	if pkg == "" && name == "" {
		return NoLabel, fmt.Errorf("label parse error: empty package and name: %q", origStr)
	}
	if name == "" {
		name = path.Base(pkg)
	}

	return Label{
		Repo:     repo,
		Pkg:      pkg,
		Name:     name,
		Relative: relative,
	}, nil
}

func (l Label) String() string {
	if l.Relative {
		return fmt.Sprintf(":%s", l.Name)
	}

	var repo string
	if l.Repo != "" && l.Repo != "@" {
		repo = fmt.Sprintf("@%s", l.Repo)
	} else {
		// if l.Repo == "", the label string will begin with "//"
		// if l.Repo == "@", the label string will begin with "@//"
		repo = l.Repo
	}

	if path.Base(l.Pkg) == l.Name {
		return fmt.Sprintf("%s//%s", repo, l.Pkg)
	}
	return fmt.Sprintf("%s//%s:%s", repo, l.Pkg, l.Name)
}

// Abs computes an absolute label (one with a repository and package name)
// from this label. If this label is already absolute, it is returned
// unchanged.
func (l Label) Abs(repo, pkg string) Label {
	if !l.Relative {
		return l
	}
	return Label{Repo: repo, Pkg: pkg, Name: l.Name}
}

// Rel attempts to compute a relative label from this label. If this label
// is already relative or is in a different package, this label may be
// returned unchanged.
func (l Label) Rel(repo, pkg string) Label {
	if l.Relative || l.Repo != repo {
		return l
	}
	if l.Pkg == pkg {
		return Label{Name: l.Name, Relative: true}
	}
	return Label{Pkg: l.Pkg, Name: l.Name}
}

// Equal returns whether two labels are exactly the same. It does not return
// true for different labels that refer to the same target.
func (l Label) Equal(other Label) bool {
	return l.Repo == other.Repo &&
		l.Pkg == other.Pkg &&
		l.Name == other.Name &&
		l.Relative == other.Relative
}

// Contains returns whether other is contained by the package of l or a
// sub-package. Neither label may be relative.
func (l Label) Contains(other Label) bool {
	if l.Relative {
		log.Panicf("l must not be relative: %s", l)
	}
	if other.Relative {
		log.Panicf("other must not be relative: %s", other)
	}
	result := l.Repo == other.Repo && pathtools.HasPrefix(other.Pkg, l.Pkg)
	return result
}

var nonWordRe = regexp.MustCompile(`\W+`)

// ImportPathToBazelRepoName converts a Go import path into a bazel repo name
// following the guidelines in http://bazel.io/docs/be/functions.html#workspace
func ImportPathToBazelRepoName(importpath string) string {
	importpath = strings.ToLower(importpath)
	components := strings.Split(importpath, "/")
	labels := strings.Split(components[0], ".")
	reversed := make([]string, 0, len(labels)+len(components)-1)
	for i := range labels {
		l := labels[len(labels)-i-1]
		reversed = append(reversed, l)
	}
	repo := strings.Join(append(reversed, components[1:]...), ".")
	return nonWordRe.ReplaceAllString(repo, "_")
}

// ModulePathToBazelRepoNameOneToOne maps a Go module path to a Bazel repository
// name in a reversible manner. The resulting repository name is also a valid
// Bazel module name.
// '/' is mapped to '_' and '.' as well as '-' are preserved, so that typical Go
// module paths transform as follows:
//
// gopkg.in/yaml.v3         --> gopkg.in_yaml.v3
// github.com/goccy/go-yaml --> github.com_goccy_go-yaml
//
// Note: Module paths are sometimes also referred to as import paths even though
// most modules' top-level directories are not valid Go packages.
func ModulePathToBazelRepoNameOneToOne(modulePath string) string {
	// Bazel repository names can contain A-Z, a-z, 0-9, '_', '-', and '.', but
	// using uppercase characters is discouraged and may not work on Windows.
	// Bazel module names are restricted further in that they can only start
	// with a letter and can only end with a letter or digit.
	// Go module paths can contain A-Z, a-z, 0-9, '_', '-', '.', '/', and '~'.
	// See:
	// https://cs.opensource.google/bazel/bazel/+/c7792e2376c735f3cb3594bfcd69f6d84f8205b7:src/main/java/com/google/devtools/build/lib/cmdline/RepositoryName.java;l=40
	// https://go.dev/ref/mod#go-mod-file-ident
	//
	// We thus choose the following escaping scheme, optimizing for the common
	// characters '/' and '-' at the cost of making the escape sequences for
	// relatively uncommon characters ('_' and 'A' to 'Z') and extremely
	// uncommon characters ('~', leading digit, trailing dash) longer:
	//
	// 1. If the module path starts with any character C that requires escaping
	//    or is a digit, replace it with "a~C.a".
	// 2. If the module path ends with a character that is neither a letter nor
	//    a digit, append "/con".
	// 3. '_' is mapped to "._."
	// 4. '~' is mapped to "._-"
	// 5. 'A' to 'Z' is mapped to "._a" to "._z"
	// 6. '/' is mapped to '_'
	//
	// This mapping is reversible because of the following two restrictions on a
	// valid Go module path:
	//
	// "A path element may not begin or end with a dot."
	//
	// This means that a valid Go module path will never contain the substring
	// "./", thus "._" in a Bazel repository name unambiguously corresponds to
	// an escape character: "./" can't be contained in the input in the first
	// place and any "._" in the input would have been escaped as ".._.".
	//
	// "The element prefix up to the first dot must not end with a tilde
	//  followed by one or more digits."
	//
	// This means that a valid Go module path will never start with the prefix
	// "a~N.a", where N is any digit.
	//
	// "The element prefix up to the first dot must not be a reserved file name
	//  on Windows, regardless of case (CON, com1, NuL, and so on)."
	//
	// This means that a valid Go module path will never end in "/con", making
	// this a valid padding string to append to the end.

	// Module paths are always non-empty.
	first := rune(modulePath[0])
	// Leading characters are further restricted by:
	// "The leading path element (up to the first slash, if any), by convention
	//  a domain name, must contain only lower-case ASCII letters, ASCII digits,
	//  dots (., U+002E), and dashes (-, U+002D); it must contain at least one
	//  dot and cannot start with a dash."
	// In fact, it also can't start with a dot: Domain names aren't allowed to
	// start with '.' and neither are module paths accepted by module.CheckPath.
	// To be on the safe side, we check for '.' here as well.
	if unicode.IsDigit(first) || unicode.IsUpper(first) || first == '_' || first == '.' {
		modulePath = fmt.Sprintf("a~%c.a%s", first, modulePath[1:])
	}

	last := rune(modulePath[len(modulePath)-1])
	if !unicode.IsDigit(last) && !unicode.IsLetter(last) {
		modulePath += "/con"
	}

	var repoName strings.Builder
	for _, r := range modulePath {
		switch {
		case r == '_':
			repoName.WriteString("._.")
		case r == '~':
			repoName.WriteString("._-")
		case r == '/':
			repoName.WriteString("_")
		case r >= 'A' && r <= 'Z':
			repoName.WriteString("._" + strings.ToLower(string(r)))
		default:
			repoName.WriteRune(r)
		}
	}
	return repoName.String()
}

var escapedLeadingCharacterPattern = regexp.MustCompile(`^a~(.)\.a`)

// BazelRepoNameToModulePathOneToOne maps a Bazel repository name obtained from
// ModulePathToBazelRepoNameOneToOne back to a Go module path.
func BazelRepoNameToModulePathOneToOne(repoName string) (string, error) {
	// See the implementation comment in BazelRepoNameToModulePathOneToOne.
	var mp strings.Builder
	pos := 0
	for pos < len(repoName) {
		c := repoName[pos]
		if c == '_' {
			mp.WriteRune('/')
			pos++
			continue
		}
		if c != '.' || pos+1 == len(repoName) || repoName[pos+1] != '_' {
			mp.WriteRune(rune(c))
			pos++
			continue
		}
		if pos+2 == len(repoName) {
			return "", errors.New("invalid escape sequence '._' at end of string")
		}
		c = repoName[pos+2]
		switch {
		case c == '.':
			mp.WriteRune('_')
		case c == '-':
			mp.WriteRune('~')
		case c >= 'a' && c <= 'z':
			mp.WriteString(strings.ToUpper(string(c)))
		default:
			return "", fmt.Errorf("invalid escape sequence '._%c' at end of string", c)
		}
		pos += 3
	}
	return strings.TrimSuffix(escapedLeadingCharacterPattern.ReplaceAllString(mp.String(), "$1"), "/con"), nil
}
