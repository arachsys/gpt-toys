declare-option str roleplay_api "https://openrouter.ai/api/v1/chat/completions"
declare-option str roleplay_key "openrouter"
declare-option str roleplay_model "x-ai/grok-4"
declare-option int roleplay_timeout 0

declare-option str roleplay_prompt %{
  You are an imaginative storyteller collaborating with the user to create
  an engaging story. The user sets the scene and writes their character's
  dialogue, thoughts, and actions in first person. Your role is to write
  the dialogue, thoughts, and actions of other characters, keeping them
  consistent with their established motivations, limitations, personality,
  and backstory.

  Generate responses of around fifty words, broken into short paragraphs
  where appropriate. Follow the tone and instructions provided (including
  notes in brackets). Maintain a natural narrative flow, without directly
  addressing the user. Incorporate moments of tension or reflection as
  needed, and stop where you expect the user's character to act or speak.
}

define-command roleplay %{
  echo -markup '{Information}waiting for shell command to finish'
  execute-keys '<c-l>'

  evaluate-commands -no-hooks -save-regs st %{
    set-register s '{Error}content generation interrupted'
    execute-keys -draft 'l{p<a-}>p;Gk"ty'

    set-register t %sh{
      if test -n "$BASH_VERSION"; then
        set -o pipefail
        shopt -s extglob
        export LANG=C.UTF-8
      else
        echo "set-register s '{Error}kakoune POSIX shell is not bash'" \
          > "$kak_command_fifo"
        exit 1
      fi

      if [[ ! -r ~/.config/secrets/$kak_opt_roleplay_key ]]; then
        echo "set-register s '{Error}$kak_opt_roleplay_key: key not found'" \
          > "$kak_command_fifo"
        exit 1
      fi

      exec 3<<EOF
{
  "model": env.kak_opt_roleplay_model,
  "messages": [
    { "role": "developer", "content": env.kak_opt_roleplay_prompt },
    { "role": "user", "content": . }
  ],
  "store": false
}
EOF

      exec 4<<EOF
Authorization: Bearer $(< ~/.config/secrets/"$kak_opt_roleplay_key")
Content-Type: application/json
EOF

      exec 5<<EOF
try (
  .choices | map(
    .message.content,
    if .finish_reason == "stop" then
      empty
    else
      "[Truncated: \\(.finish_reason)]"
    end
  ) | join("\\n\\n") + "\\n"
    | gsub("[‘’]"; "'")
    | gsub("[“”]"; "\\"")
    | gsub("…"; "...")
    | gsub(" ?— ?"; " - ")
),
"[Error: \\(.error.message? // empty)]\\n"
EOF

      kak_opt_roleplay_prompt=${kak_opt_roleplay_prompt//$'\n'*( )/$'\n'}
      kak_opt_roleplay_prompt=${kak_opt_roleplay_prompt##*($'\n')}
      kak_opt_roleplay_prompt=${kak_opt_roleplay_prompt%%*($'\n')}
      export kak_opt_roleplay_prompt

      printf "echo -to-file '%s' %%reg{t}\n" \
        "${kak_response_fifo//\'/\'\'}" > "$kak_command_fifo"
      jq -f /dev/fd/3 -s -R "$kak_response_fifo" \
        | curl -d @- -m "$kak_opt_roleplay_timeout" -s -H @/dev/fd/4 \
            --fail-with-body "$kak_opt_roleplay_api" \
        | jq -e -f /dev/fd/5 -r \
        | fmt -u -w "$kak_opt_autowrap_column"
      set $? ${PIPESTATUS[@]}

      if [[ $3 -eq 6 ]] || [[ $3 -eq 7 ]]; then
        echo "set-register s '{Error}failed to connect to host'"
      elif [[ $3 -eq 28 ]]; then
        echo "set-register s '{Error}content generation timed out'"
      elif [[ $3 -ne 0 ]]; then
        echo "set-register s '{Error}content generation failed: $3'"
      elif [[ $4 -ne 0 ]]; then
        echo "set-register s '{Error}invalid response from model'"
      else
        echo "set-register s"
      fi > "$kak_command_fifo"
    }

    echo -markup %reg{s}
    execute-keys 'l{p<a-}>p;"tp<a-O>'

    try %{
      execute-keys -draft '<a-K>.\n\z<ret>u'
    } catch %{
      execute-keys -draft 'lGes\A\s*\z<ret>d'
    } catch %{
      execute-keys -draft 'lGes\A\s*\n<ret>d2<a-O>'
    }
  }
}

hook global BufCreate .*/roleplay/.* %{
  map -docstring 'generate new roleplay content' \
    buffer user <space> ':roleplay<ret>'
  set buffer filetype markdown
}
