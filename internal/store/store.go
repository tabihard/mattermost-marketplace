package store

import "github.com/manybugsdev/mattermost-marketplace/internal/model"

// Store describes the interface to the backing store.
type Store interface {
	GetPlugins(filter *model.PluginFilter) ([]*model.Plugin, error)
}
