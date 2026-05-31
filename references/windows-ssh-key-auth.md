# Windows SSH Key Auth (<windows-ip>)

What was configured:

- Generated keypair on Linux with Dropbear-compatible format:
  - Private: `/home/petalinux/.ssh/id_dropbear_rsa`
  - Public:  `/home/petalinux/.ssh/id_dropbear_rsa.pub`
- Installed public key on Windows for:
  - `C:\ProgramData\ssh\administrators_authorized_keys`
  - `C:\Users\Administrator\.ssh\authorized_keys`

Test command:

```bash
ssh -i /home/petalinux/.ssh/id_dropbear_rsa <windows-user>@<windows-ip> whoami
```

Expected result:

```text
csg1175-p\administrator
```

Notes:

- Your `ssh` binary in this environment is Dropbear (`ssh` client), which supports the `-i` key option but not all OpenSSH conveniences.
- Passwordless login works now from this Linux host with the key above.
- Keep `/home/petalinux/.ssh/id_dropbear_rsa` private (permission `600`).
