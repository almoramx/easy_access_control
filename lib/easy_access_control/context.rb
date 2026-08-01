module EasyAccessControl
  Context = Data.define(:subject, :scope) do
    def self.unwrap(user)
      user.is_a?(self) ? [user.subject, user.scope] : [user, nil]
    end
  end
end
