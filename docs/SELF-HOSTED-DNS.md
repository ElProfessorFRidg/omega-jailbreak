# Self-hosted DNS (NextDNS-like) sur ton VPS — pour bloquer la révocation Apple

Objectif : un résolveur DNS **filtrant**, chiffré (DoH/DoT), **sans limite de requêtes**,
entièrement sous ton contrôle — l'équivalent de NextDNS mais self-hosted. Il laisse
passer tout Internet **sauf** les 4 domaines qu'iOS utilise pour (re)révoquer les
certificats, ce qui empêche le retour du message « Vérifier l'app » quand l'iPad est
en ligne.

Domaines bloqués (extraits de tes vrais certificats + l'endpoint entreprise) :

```
ocsp.apple.com      → vérification de révocation (marque les certs REVOKED)
ppq.apple.com       → contrôle de confiance "entreprise" (le bouton "Vérifier l'app")
crl.apple.com       → liste de révocation
valid.apple.com     → base "Valid" de révocation
```

> ⚠️ Rappel : le blocage réseau est **obligatoire** pour l'usage en ligne. La
> neutralisation locale sur l'iPad (ban-lists vides + `schg`, `ocspcache` purgé) ne
> tient qu'hors-ligne ; dès que l'appareil joint Internet sans ce blocage, `amfid`
> re-vérifie en direct et rebloque. Et `/etc/hosts` est en lecture seule sur un
> jailbreak rootless → le blocage **doit** se faire hors de l'appareil (ici, ton VPS).

---

## 0. Prérequis

- Un VPS Linux (Debian/Ubuntu recommandé) avec IP publique.
- Un **nom de domaine** pointant sur le VPS (ex. `dns.tondomaine.com`, enregistrement `A`
  → IP du VPS). Indispensable pour un certificat TLS valide (DoH/DoT).
- Accès root / sudo.

---

## 1. ⚠️ Sécurité : NE PAS faire un "open resolver"

C'est LE point critique. Un DNS en UDP/53 ouvert à tout Internet =
**open resolver** → exploité pour des attaques par amplification DDoS → ton
hébergeur suspend le VPS.

Règles SAFE :

1. **N'expose publiquement que DoH (443) et/ou DoT (853)** — pas l'UDP/53.
2. **Ferme le port 53 au monde** au pare-feu (il ne sert qu'en local, à AdGuard Home).
3. Utilise un **domaine + certificat TLS** : l'URL DoH fait office de secret et tout
   est chiffré, même sur réseau mobile.

---

## 2. Installer AdGuard Home

```bash
curl -s -S -L https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | sh -s -- -v
```

Ça installe et démarre un service `AdGuardHome`. Ouvre l'assistant web :

```
http://IP_DU_VPS:3000
```

- Crée ton compte admin.
- **Listen interface** pour le DNS : laisse `All interfaces`, port **53**
  (on le fermera au pare-feu juste après — il reste accessible en local).
- Interface d'admin : port `3000` (ou `80`, au choix).

---

## 3. Certificat TLS (Let's Encrypt)

AdGuard Home chiffre DoH/DoT avec un certificat. Le plus simple : `certbot` en mode
standalone, puis on pointe AGH sur les fichiers générés.

```bash
sudo apt update && sudo apt install -y certbot
# le port 80 doit être libre le temps de la génération
sudo certbot certonly --standalone -d dns.tondomaine.com
```

Les fichiers sont dans :

```
/etc/letsencrypt/live/dns.tondomaine.com/fullchain.pem
/etc/letsencrypt/live/dns.tondomaine.com/privkey.pem
```

> AdGuard Home tourne souvent sous un utilisateur non-root : donne-lui l'accès en
> lecture au dossier, ou copie les certs et ajuste les droits. Pense à automatiser le
> renouvellement (`certbot renew` via cron/systemd-timer) + recharger AGH.

---

## 4. Activer DoH / DoT (Encryption settings)

Dans l'UI AdGuard Home → **Settings → Encryption settings** :

- **Enable encryption** ✅
- **Server name** : `dns.tondomaine.com`
- **Certificates** : chemin vers `fullchain.pem` (ou colle le contenu)
- **Private key** : chemin vers `privkey.pem`
- **HTTPS port** : `443` (DoH)   → endpoint : `https://dns.tondomaine.com/dns-query`
- **DNS-over-TLS port** : `853` (DoT) → `tls://dns.tondomaine.com`

Upstream (résolveurs en amont, dans **Settings → DNS settings → Upstream DNS servers**),
ex. en DoH pour que tout reste chiffré de bout en bout :

```
https://dns.quad9.net/dns-query
https://cloudflare-dns.com/dns-query
```

---

## 5. Pare-feu (le cœur du "SAFE")

Avec `ufw` (adapte si tu utilises nftables / le firewall de l'hébergeur) :

```bash
sudo ufw allow 22/tcp            # SSH (garde-le !)
sudo ufw allow 443/tcp           # DoH
sudo ufw allow 853/tcp           # DoT
sudo ufw deny 53                 # bloque le DNS clair au monde (open resolver)
# l'admin 3000 : ne pas l'exposer publiquement -> via SSH tunnel, ou restreint à ton IP
sudo ufw enable
sudo ufw status verbose
```

> Résultat : personne ne peut t'utiliser comme resolver clair ; seuls DoH/DoT
> (chiffrés, avec ton domaine) sont accessibles. Pas de risque d'amplification.

Option « ceinture + bretelles » : dans AdGuard Home → **Settings → DNS settings →
Access settings**, tu peux lister des *Allowed clients* (mais une IP mobile change,
donc le DoH-par-domaine est déjà ta protection principale).

---

## 6. Les règles de blocage (les 4 domaines Apple)

Deux méthodes équivalentes, choisis-en une.

**A. DNS rewrites** (Filters → DNS rewrites → Add) — mappe chaque domaine vers `0.0.0.0` :

| Domain            | Answer   |
|-------------------|----------|
| `ocsp.apple.com`  | 0.0.0.0  |
| `ppq.apple.com`   | 0.0.0.0  |
| `crl.apple.com`   | 0.0.0.0  |
| `valid.apple.com` | 0.0.0.0  |

**B. Custom filtering rules** (Filters → Custom filtering rules) :

```
||ocsp.apple.com^
||ppq.apple.com^
||crl.apple.com^
||valid.apple.com^
```

> Ne bloque **pas** `certs.apple.com` (téléchargement du certificat CA, pas de la
> révocation). Tout le reste d'Internet continue de résoudre normalement.

---

## 7. Côté iPad : profil DoH (Wi-Fi + 4G, permanent)

Le fichier **`Omega-DoH.mobileconfig`** (dans ce dossier) est un profil DoH prêt à
l'emploi. Ouvre-le, remplace l'URL :

```xml
<key>ServerURL</key>
<string>https://dns.tondomaine.com/dns-query</string>
```

Puis transfère-le sur l'iPad (AirDrop / mail / page web) →
**Réglages → Profil téléchargé → Installer**.

À partir de là, **tout** le trafic DNS de l'iPad (Wi-Fi et cellulaire) passe par ton
VPS en chiffré, et les 4 domaines Apple sont bloqués. Sans quota.

---

## 8. Vérifier

Depuis un poste / le VPS :

```bash
# résolution normale (doit répondre une IP réelle)
dig +short @127.0.0.1 example.com
# domaine bloqué (doit répondre 0.0.0.0 ou vide)
dig +short @127.0.0.1 ppq.apple.com

# test du endpoint DoH public
curl -s 'https://dns.tondomaine.com/dns-query?name=ppq.apple.com&type=A' \
     -H 'accept: application/dns-json'
```

Sur l'iPad : Réglages → Général → VPN/Gestion des appareils → le profil est actif ;
dans AdGuard Home → **Query Log**, tu vois les requêtes de l'iPad et les 4 domaines
Apple marqués *Blocked*.

---

## 9. Maintenance

- **Renouvellement TLS** : `certbot renew` (cron/timer) + recharger AGH après renouvellement.
- **Mises à jour** : `AdGuardHome -s stop && AdGuardHome --update && AdGuardHome -s start`
  (ou via l'UI).
- **Logs** : garde un œil sur le Query Log au début pour confirmer que rien d'utile
  n'est bloqué par erreur.

---

## Alternatives (plus légères, sans UI)

**dnsmasq** (ultra-léger, mais DNS clair → à restreindre par pare-feu, pas de DoH natif) :

```
# /etc/dnsmasq.d/omega.conf
server=1.1.1.1
address=/ocsp.apple.com/0.0.0.0
address=/ppq.apple.com/0.0.0.0
address=/crl.apple.com/0.0.0.0
address=/valid.apple.com/0.0.0.0
```
Pour le DoH par-dessus, il faut ajouter un proxy (ex. `dnsproxy`/`cloudflared`).
→ Pour du mobile, **AdGuard Home** reste le plus simple (DoH/DoT intégrés).

**Pi-hole** : équivalent à AdGuard Home côté filtrage, mais le DoH/DoT demande un
composant séparé (cloudflared / dnsdist). AdGuard Home fait tout nativement.
