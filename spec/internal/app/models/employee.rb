class Employee < ActiveRecord::Base
  include EasyAccessControl::Subject
end
