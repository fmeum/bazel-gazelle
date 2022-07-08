/* Copyright 2022 The Bazel Authors. All rights reserved.

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

package main

import (
	"bufio"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
)

func main() {
	log.SetFlags(0)
	log.SetPrefix("gzlmod: ")

	if flag.NArg() != 2 {
		log.Fatal("fetch_repo takes two positional arguments")
	}
}

func listVersions(proxy string, importpath string) ([]string, error) {
	resp, err := http.Get(moduleVersionsUrl(proxy, importpath))
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	s := bufio.NewScanner(resp.Body)
	var versions []string
	for s.Scan() {
		versions = append(versions, s.Text())
	}
	return versions, nil
}

func downloadModule(importpath string, version string) (*GoModule, error) {
	cmd := exec.Command("go", "mod", "download", "-json", fmt.Sprintf("%s@v%s", importpath, version))
	out, err := cmd.Output()
	if err != nil {
		return nil, err
	}
	goModule := &GoModule{}
	err = json.Unmarshal(out, goModule)
	if err != nil {
		return nil, err
	}
	if goModule.Error != "" {
		return nil, errors.New(goModule.Error)
	}
	return goModule, err
}

func copyToTmpDir(dir string) (string, error) {
	tmp, err := ioutil.TempDir("", "gzlmod-*")
	if err != nil {
		return "", err
	}
	err = filepath.Walk(dir, func(src string, info os.FileInfo, e error) (err error) {
		if e != nil {
			return e
		}
		rel, err := filepath.Rel(dir, src)
		if err != nil {
			return err
		}
		if rel == "." {
			return nil
		}
		dest := filepath.Join(tmp, rel)

		if info.IsDir() {
			return os.Mkdir(dest, 0o777)
		} else {
			r, err := os.Open(src)
			if err != nil {
				return err
			}
			defer r.Close()
			w, err := os.Create(dest)
			if err != nil {
				return err
			}
			defer func() {
				if cerr := w.Close(); err == nil && cerr != nil {
					err = cerr
				}
			}()
			_, err = io.Copy(w, r)
			return err
		}
	})
	if err != nil {
		return "", err
	}
	return tmp, nil
}

func hashFile(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	h := sha256.New()
	_, err = io.Copy(h, f)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("sha256-" + base64.StdEncoding.EncodeToString(h.Sum(nil))), nil
}

func writeSourceJson(proxy string, importpath string, version string) error {

}

func writeMetadataJson(importpath string, versions []string) error {
	path := filepath.Join("modules", toModuleName(importpath), "metadata.json")
	metadata := ModuleMetadata{
		Homepage: "https://" + importpath,
		Versions: versions,
	}
}

func moduleZipUrl(proxy string, importpath string, version string) string {
	return fmt.Sprintf("%s/%s/@v/%s.zip", proxy, importpath, version)
}

func moduleVersionsUrl(proxy string, importpath string) string {
	return fmt.Sprintf("%s/%s/@v/list", proxy, importpath)
}

func toModuleName(importpath string) string {

}

func toRepoName(importpath string) string {

}

type ModuleMetadata struct {
	Homepage string   `json:"homepage"`
	Versions []string `json:"versions"`
}

type ModuleSource struct {
	Integrity   string            `json:"integrity"`
	PatchStrip  int               `json:"patch_strip,omitempty"`
	Patches     map[string]string `json:"patches,omitempty"`
	StripPrefix string            `json:"strip_prefix,omitempty"`
	Url         string            `json:"url"`
}

type GoModule struct {
	Path     string // module path
	Version  string // module version
	Error    string // error loading module
	Info     string // absolute path to cached .info file
	GoMod    string // absolute path to cached .mod file
	Zip      string // absolute path to cached .zip file
	Dir      string // absolute path to cached source root directory
	Sum      string // checksum for path, version (as in go.sum)
	GoModSum string // checksum for go.mod (as in go.sum)
}
