#!/usr/bin/env python3
from flask import Flask, jsonify, make_response
from flask import render_template
from flask import request
from cql import Query

class DB():
    q = None
    remote_opened = False
    @classmethod
    def init(cls, ip, port, user, password):
        if not cls.q:
            cls.q = Query(ip, port, user, password, debug=True)

    @classmethod
    def ssh(cls, ip, user, password):
        if not cls.remote_opened:
            cls.q.open(ip, user, password)
            cls.remote_opened = True

    @classmethod
    def close_ssh(cls):
        cls.q.close()

    @classmethod
    def query(cls, cql):
        return cls.q.query(cql)

app = Flask(__name__, template_folder='view')

#@app.route('/', methods=['GET'])
@app.route('/')
def main():
    return render_template('login.html', page_title='Cassandra DB')

@app.route('/db', methods=['POST'])
def db():
    rows = []
    keyspaces = set()
    tables = []
    ip = request.form.get('ip')
    port = request.form.get('port')
    user = request.form.get('user')
    password = request.form.get('password')
    ssh = request.form.get('ssh')
    ssh_ip = request.form.get('ssh_ip')
    ssh_user = request.form.get('ssh_user')
    ssh_password = request.form.get('ssh_password')

    if ip and port and user and password:
        DB.init(ip, port, user, password)
        if ssh:
            DB.ssh(ssh_ip, ssh_user, ssh_password)
        rows, tm, page = DB.query('SELECT keyspace_name, table_name FROM system_schema.tables')
        if not rows:
            rows = []
        for row in rows:
            if not row['keyspace_name'].startswith('system'):
                keyspaces.add(row['keyspace_name'])
                tables.append(row['table_name'])

    return render_template('db.html', query_time=tm, keyspaces=keyspaces, tables=tables, rows=rows)

@app.errorhandler(404)
def not_found(error):
    return make_response(jsonify({'error': 'Not found'}), 404)

if __name__ == '__main__':
    app.run(host="0.0.0.0", port=80, debug=True)