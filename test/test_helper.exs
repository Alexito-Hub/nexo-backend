# Los tests corren contra la base `nexo_test` del cluster: se limpia al inicio
# para que cada corrida sea reproducible.
for collection <- ["teachers", "refresh_tokens", "audit_log"] do
  Mongo.delete_many(Nexo.Db.conn(), collection, %{})
end

ExUnit.start()
