/* Copyright 2017 The Bazel Authors. All rights reserved.

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

package label

import (
	"golang.org/x/mod/module"
	"reflect"
	"regexp"
	"testing"
)

func TestLabelString(t *testing.T) {
	for _, spec := range []struct {
		l    Label
		want string
	}{
		{
			l:    Label{Name: "foo"},
			want: "//:foo",
		}, {
			l:    Label{Pkg: "foo/bar", Name: "baz"},
			want: "//foo/bar:baz",
		}, {
			l:    Label{Pkg: "foo/bar", Name: "bar"},
			want: "//foo/bar",
		}, {
			l:    Label{Repo: "com_example_repo", Pkg: "foo/bar", Name: "baz"},
			want: "@com_example_repo//foo/bar:baz",
		}, {
			l:    Label{Repo: "com_example_repo", Pkg: "foo/bar", Name: "bar"},
			want: "@com_example_repo//foo/bar",
		}, {
			l:    Label{Relative: true, Name: "foo"},
			want: ":foo",
		}, {
			l:    Label{Repo: "@", Pkg: "foo/bar", Name: "baz"},
			want: "@//foo/bar:baz",
		},
	} {
		if got, want := spec.l.String(), spec.want; got != want {
			t.Errorf("%#v.String() = %q; want %q", spec.l, got, want)
		}
	}
}

func TestParse(t *testing.T) {
	for _, tc := range []struct {
		str     string
		want    Label
		wantErr bool
	}{
		{str: "", wantErr: true},
		{str: "@//:", wantErr: true},
		{str: "@a:b", wantErr: true},
		{str: "@a//", wantErr: true},
		{str: "@//:a", want: Label{Repo: "@", Name: "a", Relative: false}},
		{str: "@//a:b", want: Label{Repo: "@", Pkg: "a", Name: "b"}},
		{str: ":a", want: Label{Name: "a", Relative: true}},
		{str: "a", want: Label{Name: "a", Relative: true}},
		{str: "//:a", want: Label{Name: "a", Relative: false}},
		{str: "//a", want: Label{Pkg: "a", Name: "a"}},
		{str: "//a/b", want: Label{Pkg: "a/b", Name: "b"}},
		{str: "//a:b", want: Label{Pkg: "a", Name: "b"}},
		{str: "@a", want: Label{Repo: "a", Pkg: "", Name: "a"}},
		{str: "@a//b", want: Label{Repo: "a", Pkg: "b", Name: "b"}},
		{str: "@a//b:c", want: Label{Repo: "a", Pkg: "b", Name: "c"}},
		{str: "@a//@b:c", want: Label{Repo: "a", Pkg: "@b", Name: "c"}},
		{str: "@..//b:c", want: Label{Repo: "..", Pkg: "b", Name: "c"}},
		{str: "@--//b:c", want: Label{Repo: "--", Pkg: "b", Name: "c"}},
		{str: "//api_proto:api.gen.pb.go_checkshtest", want: Label{Pkg: "api_proto", Name: "api.gen.pb.go_checkshtest"}},
		{str: "@go_sdk//:src/cmd/go/testdata/mod/rsc.io_!q!u!o!t!e_v1.5.2.txt", want: Label{Repo: "go_sdk", Name: "src/cmd/go/testdata/mod/rsc.io_!q!u!o!t!e_v1.5.2.txt"}},
		{str: "//:a][b", want: Label{Name: "a][b"}},
		{str: "//:a b", want: Label{Name: "a b"}},
	} {
		got, err := Parse(tc.str)
		if err != nil && !tc.wantErr {
			t.Errorf("for string %q: got error %s ; want success", tc.str, err)
			continue
		}
		if err == nil && tc.wantErr {
			t.Errorf("for string %q: got label %s ; want error", tc.str, got)
			continue
		}
		if !reflect.DeepEqual(got, tc.want) {
			t.Errorf("for string %q: got %s ; want %s", tc.str, got, tc.want)
		}
	}
}

func TestImportPathToBazelRepoName(t *testing.T) {
	for path, want := range map[string]string{
		"git.sr.ht/~urandom/errors": "ht_sr_git_urandom_errors",
		"golang.org/x/mod":          "org_golang_x_mod",
	} {
		if got := ImportPathToBazelRepoName(path); got != want {
			t.Errorf(`ImportPathToBazelRepoName(%q) = %q; want %q`, path, got, want)
		}
	}
}

var bazelRepoNamePattern = regexp.MustCompile(`^[a-z][a-z0-9_.-]*[a-z0-9]$`)

func TestModulePathToBazelRepoNameAndBack(t *testing.T) {
	for _, modulePath := range []string{
		"gopkg.in/yaml.v3",
		"golang.org/x/mod",
		"git.sr.ht/~urandom/errors",
		"1example.org/foo/foo_bar-",
		".example.org/foo/foo_bar_",
		".example.org/foo/foo_bar~",
		"example.org/~/~_/_/_~/__/_._/_.__._.__/foobar",
		"example.org/~/~_A/A_/_B~/_C_/_.C_/_._C_._C._C_/foobar",
	} {
		repoName := ModulePathToBazelRepoNameOneToOne(modulePath)
		if !bazelRepoNamePattern.MatchString(repoName) {
			t.Errorf("ModulePathToBazelRepoNameOneToOne(%q) = %q is not a valid repo name", modulePath, repoName)
		}
		if got, err := BazelRepoNameToModulePathOneToOne(repoName); got != modulePath || err != nil {
			t.Errorf(
				"ModulePathToBazelRepoNameOneToOne(%q) = %q\nBazelRepoNameToModulePathOneToOne(ModulePathToBazelRepoNameOneToOne(%q)) = %q; want %q",
				modulePath,
				repoName,
				modulePath,
				got,
				modulePath,
			)
		}
	}
}

func FuzzModulePathToBazelRepoNameAndBack(f *testing.F) {
	f.Add("gopkg.in/yaml.v3")
	f.Add("golang.org/x/mod")
	f.Add("git.sr.ht/~urandom/errors")
	f.Add("1example.org/foo/foo_bar")
	f.Add("Aexample.org/foo/foo_bar")
	f.Add("_example.org/foo/foo_bar")
	f.Add("~example.org/foo/foo_bar")
	f.Add(".example.org/foo/foo_bar")
	f.Add("example.org/~/~_/_/_~/__/_._/_._._._/foobar")
	f.Add("example.org/~/~_A/A_/_B~/_C_/_.C_/_._C_._C._C_/foobar")
	f.Add("/con")
	f.Fuzz(func(t *testing.T, modulePath string) {
		err := module.CheckPath(modulePath)
		if err != nil {
			return
		}
		repoName := ModulePathToBazelRepoNameOneToOne(modulePath)
		if !bazelRepoNamePattern.MatchString(repoName) {
			t.Errorf("ModulePathToBazelRepoNameOneToOne(%q) = %q is not a valid repo name", modulePath, repoName)
		}
		if got, err := BazelRepoNameToModulePathOneToOne(repoName); got != modulePath || err != nil {
			t.Errorf(
				"ModulePathToBazelRepoNameOneToOne(%q) = %q\nBazelRepoNameToModulePathOneToOne(ModulePathToBazelRepoNameOneToOne(%q)) = %q; want %q",
				modulePath,
				repoName,
				modulePath,
				got,
				modulePath,
			)
		}
	})
}
