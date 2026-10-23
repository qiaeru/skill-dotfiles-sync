# SSH: ~/.ssh

The hook syncs `~/.ssh/config`, every file under `~/.ssh/config.d/`, and the public keys (`~/.ssh/*.pub`). Everything else in `~/.ssh` is left alone unless the person asks for it: private keys, `known_hosts`, `authorized_keys`, `agent/` and its sockets.

A `config.d/` folder is a convention, not an SSH default. It only works with `Include config.d/*` at the top of `~/.ssh/config`.

`~/.ssh` must stay closed to other users, or SSH refuses the keys inside. The hook marks the `.ssh` and `.claude` source folders `private_`, so chezmoi writes them as 700 on Linux and macOS whatever OS added them first.

## Private keys

First, advise against syncing them. One key per machine is the safer default: a lost laptop means revoking one key on GitHub and the servers, not every key the person owns. A synced private key is as safe as the age key: whoever holds `key.txt` and the repo holds the SSH key too.

If the person still wants a key on every machine:

1. Check that the key has a passphrase (`ssh-keygen -y -f ~/.ssh/<key>` asks for it if it has one). Suggest adding one with `ssh-keygen -p -f ~/.ssh/<key>` if not.
2. Add it encrypted and mark it private. SSH refuses a private key that others can read, and chezmoi on Windows records no file mode, so without the attribute a key added there would land on Linux and macOS readable by all:

   ```bash
   chezmoi add --encrypt ~/.ssh/<key>
   chezmoi chattr +private ~/.ssh/<key>
   ```

3. Run a sync. From then on, the hook syncs its edits and its deletion like the other files.

On Windows, a key written by chezmoi inherits the ACL of `%USERPROFILE%\.ssh`, which OpenSSH accepts. If `ssh` still reports "UNPROTECTED PRIVATE KEY FILE", reset the ACL to the owner alone:

```powershell
icacls "$env:USERPROFILE\.ssh\<key>" /inheritance:r /grant:r "${env:USERNAME}:F"
```

To stop syncing a key, run `chezmoi forget --force ~/.ssh/<key>` and a sync. The other machines keep their copy; delete it there by hand if it should go.

## known_hosts

Every machine appends to `known_hosts` on each new host, and Git cannot merge ciphertext, so a synced `known_hosts` raises a conflict whenever two machines meet a new host between two syncs. Say so before adding it with `chezmoi add --encrypt ~/.ssh/known_hosts`. A conflict on it resolves as a sorted union of both versions (`sort -u`).

## authorized_keys

It lists who may log in to this machine. Sync it only if every synced machine accepts the same logins, and confirm with the person first.

## A leaked age key

Rotate every synced private key: generate a new one, put its public key on GitHub and the servers, remove the old one there, then replace the file and sync.
