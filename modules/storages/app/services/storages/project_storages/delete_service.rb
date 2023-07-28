#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) 2012-2023 the OpenProject GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2013 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See COPYRIGHT and LICENSE files for more details.
#++

module Storages::ProjectStorages
  # Performs the deletion in the superclass. Associated FileLinks are deleted
  # by the model before_destroy hook.
  class DeleteService < ::BaseServices::Delete
    def before_perform(*)
      delete_project_folder

      super
    end

    # "persist" is a callback from BaseContracted.perform
    # that is supposed to do the actual work in a contract.
    # So in a DeleteService it performs the actual delete,
    # except for the @object.destroy that is already performed
    # by ::BaseServices::Delete
    def persist(service_result)
      # Perform the @object.destroy etc. in the super-class
      super(service_result).tap do |deletion_result|
        delete_associated_file_links if deletion_result.success?
        Helper.trigger_nextcloud_synchronization(model.project_folder_mode)
      end
    end

    private

    def delete_project_folder
      Storages::Peripherals::StorageRequests
        .new(storage: model.storage)
        .delete_folder_command
        .call(location: model.project_folder_path)
    end

    # Delete FileLinks with the same Storage as the ProjectStorage.
    # Also, they are attached to WorkPackages via the Project.
    def delete_associated_file_links
      # work_packages is an ActiveRecord::Relation, not an array of objects!
      work_packages = WorkPackage.where(project_id: model.project_id)
      file_links = Storages::FileLink.where(storage_id: model.storage_id,
                                            container: work_packages)
      # use file_links.to_sql to check the SQL generated by the lines above.
      # It uses a fast SQL "container_id in (select * from work_packages...)", so the
      # delete_all below is executed using a single query.
      # Reference: https://api.rubyonrails.org/classes/ActiveRecord/Relation.html
      file_links.delete_all
    end
  end
end
