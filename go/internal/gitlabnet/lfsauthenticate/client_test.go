package lfsauthenticate

import (
	"encoding/json"
	"io/ioutil"
	"net/http"
	"testing"

	"github.com/stretchr/testify/require"

	"gitlab.com/gitlab-org/gitlab-shell/go/internal/command/commandargs"
	"gitlab.com/gitlab-org/gitlab-shell/go/internal/config"
	"gitlab.com/gitlab-org/gitlab-shell/go/internal/gitlabnet/testserver"
)

const (
	keyId  = "123"
	repo   = "group/repo"
	action = commandargs.UploadPack
)

func setup(t *testing.T) []testserver.TestRequestHandler {
	requests := []testserver.TestRequestHandler{
		{
			Path: "/api/v4/internal/lfs_authenticate",
			Handler: func(w http.ResponseWriter, r *http.Request) {
				b, err := ioutil.ReadAll(r.Body)
				defer r.Body.Close()
				require.NoError(t, err)

				var request *Request
				require.NoError(t, json.Unmarshal(b, &request))

				switch request.KeyId {
				case keyId:
					body := map[string]interface{}{
						"username":             "john",
						"lfs_token":            "sometoken",
						"repository_http_path": "https://gitlab.com/repo/path",
						"expires_in":           1800,
					}
					require.NoError(t, json.NewEncoder(w).Encode(body))
				case "forbidden":
					w.WriteHeader(http.StatusForbidden)
				case "broken":
					w.WriteHeader(http.StatusInternalServerError)
				}
			},
		},
	}

	return requests
}

func TestFailedRequests(t *testing.T) {
	requests := setup(t)
	url, cleanup := testserver.StartHttpServer(t, requests)
	defer cleanup()

	testCases := []struct {
		desc           string
		args           *commandargs.CommandArgs
		expectedOutput string
	}{
		{
			desc:           "With bad response",
			args:           &commandargs.CommandArgs{GitlabKeyId: "-1", CommandType: commandargs.UploadPack},
			expectedOutput: "Parsing failed",
		},
		{
			desc:           "With API returns an error",
			args:           &commandargs.CommandArgs{GitlabKeyId: "forbidden", CommandType: commandargs.UploadPack},
			expectedOutput: "Internal API error (403)",
		},
		{
			desc:           "With API fails",
			args:           &commandargs.CommandArgs{GitlabKeyId: "broken", CommandType: commandargs.UploadPack},
			expectedOutput: "Internal API error (500)",
		},
	}

	for _, tc := range testCases {
		t.Run(tc.desc, func(t *testing.T) {
			client, err := NewClient(&config.Config{GitlabUrl: url}, tc.args)
			require.NoError(t, err)

			repo := "group/repo"

			_, err = client.Authenticate(tc.args.CommandType, repo, "")
			require.Error(t, err)

			require.Equal(t, tc.expectedOutput, err.Error())
		})
	}
}

func TestSuccessfulRequests(t *testing.T) {
	requests := setup(t)
	url, cleanup := testserver.StartHttpServer(t, requests)
	defer cleanup()

	args := &commandargs.CommandArgs{GitlabKeyId: keyId, CommandType: commandargs.LfsAuthenticate}
	client, err := NewClient(&config.Config{GitlabUrl: url}, args)
	require.NoError(t, err)

	response, err := client.Authenticate(action, repo, "")
	require.NoError(t, err)

	expectedResponse := &Response{
		Username:  "john",
		LfsToken:  "sometoken",
		RepoPath:  "https://gitlab.com/repo/path",
		ExpiresIn: 1800,
	}

	require.Equal(t, expectedResponse, response)
}
