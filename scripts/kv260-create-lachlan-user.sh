#!/usr/bin/env sh
set -eu

USER_NAME="${1:-lachlan}"
USER_PASS="${2:-}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Must run as root: $(id -un)" >&2
  exit 1
fi

if [ -z "${USER_NAME}" ] || printf '%s' "${USER_NAME}" | tr -d '[:alnum:]_-.' | grep -q .; then
  echo "Invalid username: ${USER_NAME}" >&2
  exit 1
fi

if [ -z "${USER_PASS}" ]; then
  echo "Usage: $0 [username] <password>" >&2
  echo "Refusing to create a user with a hardcoded default password." >&2
  exit 1
fi

if command -v getent >/dev/null 2>&1 && getent passwd "${USER_NAME}" >/dev/null 2>&1; then
  echo "User '${USER_NAME}' already exists."
else
  if command -v useradd >/dev/null 2>&1; then
    useradd -m -s /bin/bash "${USER_NAME}"
  elif command -v adduser >/dev/null 2>&1; then
    adduser -D "${USER_NAME}" >/dev/null 2>&1 || adduser "${USER_NAME}"
  else
    echo "No useradd/adduser binary available on target." >&2
    exit 1
  fi
  echo "Created user '${USER_NAME}'."
fi

echo "${USER_NAME}:${USER_PASS}" | chpasswd
echo "Set password for '${USER_NAME}'."

if command -v groupadd >/dev/null 2>&1; then
  # optional utility groups for camera/gui tool access
  for grp in video audio input render tty dialout; do
    if getent group "${grp}" >/dev/null 2>&1; then
      usermod -aG "${grp}" "${USER_NAME}" || true
    fi
  done
fi

echo "Done."
