# frozen_string_literal: true

class CreateAspaceRepositorySyncs < ActiveRecord::Migration[7.1]
  def change
    create_table :aspace_repository_syncs do |t|
      t.string :aspace_config_set, null: false
      t.string :repository_code, null: false
      t.datetime :last_synced_at, null: false
    end

    add_index :aspace_repository_syncs, %i[aspace_config_set repository_code],
              unique: true,
              name: 'index_aspace_repository_syncs_on_config_set_and_code'
  end
end
