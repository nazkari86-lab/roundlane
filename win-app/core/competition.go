package core

import (
	"bytes"
	"crypto/ed25519"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"regexp"
	"strings"
)

const MaxCompetitionBytes = 64 * 1024

var quitHashPattern = regexp.MustCompile(`^[A-Fa-f0-9]{64}$`)

type Competition struct {
	Format           string `json:"format"`
	Version          int    `json:"version"`
	GroupURL         string `json:"groupURL"`
	QuitPasswordHash string `json:"quitPasswordHash"`
	Signature        string `json:"signature,omitempty"`
}

func (c Competition) IsParticipant() bool { return c.Format == "roundlane-participant" }

func (c Competition) SigningData() []byte {
	return []byte("Roundlane participant v1\n" + c.GroupURL + "\n" + c.QuitPasswordHash + "\n")
}

func ValidPasswordHash(hash string) bool { return quitHashPattern.MatchString(hash) }

func (c Competition) Validated() (Competition, error) {
	if (c.Format != "roundlane-competition" && !c.IsParticipant()) || c.Version != 1 {
		return Competition{}, errors.New("неподдерживаемый формат или версия настроек Roundlane")
	}
	group, err := GroupURL(c.GroupURL)
	if err != nil {
		return Competition{}, err
	}
	if !ValidPasswordHash(c.QuitPasswordHash) {
		return Competition{}, errors.New("в настройках отсутствует корректный код выхода")
	}
	c.GroupURL = group
	c.QuitPasswordHash = strings.ToUpper(c.QuitPasswordHash)
	if c.IsParticipant() {
		key, _ := hex.DecodeString(RuntimePublicKey)
		sig, err := hex.DecodeString(c.Signature)
		if err != nil || len(sig) != ed25519.SignatureSize || !ed25519.Verify(key, c.SigningData(), sig) {
			return Competition{}, errors.New("подпись файла соревнования неверна. Получите исходный файл у организатора")
		}
	} else if c.Signature != "" {
		return Competition{}, errors.New("неверный формат подписи")
	}
	return c, nil
}

func NewCompetition(group, code string) (Competition, error) {
	if !ValidCode(code) {
		return Competition{}, errors.New("код: 4–32 латинских букв или цифр")
	}
	return (Competition{Format: "roundlane-competition", Version: 1, GroupURL: group, QuitPasswordHash: PasswordHash(code)}).Validated()
}

func NewParticipant(group, code string, key ed25519.PrivateKey) (Competition, error) {
	c, err := NewCompetition(group, code)
	if err != nil {
		return Competition{}, err
	}
	public, _ := hex.DecodeString(RuntimePublicKey)
	if len(key) != ed25519.PrivateKeySize || !bytes.Equal(key.Public().(ed25519.PublicKey), public) {
		return Competition{}, errors.New("неверный ключ организатора")
	}
	c.Format = "roundlane-participant"
	c.Signature = hex.EncodeToString(ed25519.Sign(key, c.SigningData()))
	return c.Validated()
}

func DecodeCompetition(data []byte) (Competition, error) {
	if len(data) > MaxCompetitionBytes {
		return Competition{}, errors.New("файл настроек слишком большой (максимум 64 КиБ)")
	}
	d := json.NewDecoder(bytes.NewReader(data))
	d.DisallowUnknownFields()
	var c Competition
	if err := d.Decode(&c); err != nil {
		return Competition{}, errors.New("повреждённый файл настроек Roundlane")
	}
	if err := d.Decode(new(interface{})); err != io.EOF {
		return Competition{}, errors.New("лишние данные в файле настроек Roundlane")
	}
	return c.Validated()
}

func (c Competition) Encode() ([]byte, error) {
	checked, err := c.Validated()
	if err != nil {
		return nil, err
	}
	data, err := json.MarshalIndent(checked, "", "  ")
	return append(data, '\n'), err
}
