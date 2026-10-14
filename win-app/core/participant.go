package core

import "errors"

// No organizer UI or plaintext code is required by this entry point.
// Persist only after the runtime confirms that the session is ready.
func LaunchParticipant(c Competition, start func(Competition) error, remember func(Competition) error) error {
	checked, err := c.Validated()
	if err != nil {
		return err
	}
	if !checked.IsParticipant() {
		return errors.New("для прямого старта нужен подписанный файл участника")
	}
	if err = start(checked); err != nil {
		return err
	}
	return remember(checked)
}
