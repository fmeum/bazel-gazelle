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

package golang

import (
	"encoding/json"
)

// DumpGoModJson returns a JSON representation of an array containing importpath, version, and sum for every module in
// the go.mod file at goModPath.
func DumpGoModJson(goModPath string) (string, error) {
	result := importReposFromGoMod(goModPath)
	var modules []*goModule
	for _, repo := range result.Gen {
		modules = append(modules, &goModule{
			Importpath: repo.AttrString("importpath"),
			Version:    repo.AttrString("version"),
			Sum:        repo.AttrString("sum"),
		})
	}
	modulesJson, err := json.Marshal(modules)
	if err != nil {
		return "", err
	}
	return string(modulesJson), nil
}

type goModule struct {
	Importpath string `json:"importpath"`
	Version    string `json:"version"`
	Sum        string `json:"sum"`
}
