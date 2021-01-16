#!/usr/bin/env python3
#coding: utf-8
from flask import Flask, jsonify, make_response
from flask import render_template, views
from flask import request, session, flash, redirect, url_for
from cql import Query
import traceback
import os
from datetime import timedelta

class DB():
    q = None
    @classmethod
    def init(cls, ip, port, user, password):
        if not cls.q:
            cls.q = Query(ip, port, user, password, debug=True)

    @classmethod
    def ssh(cls, ip, user, password):
        try:
            cls.q.open(ip, user, password)
        except Exception as e:
            cls.q = None
            traceback.print_exc()
            return e.value

    @classmethod
    def close(cls):
        if cls.q:
            cls.q.close()
            cls.q = None

    @classmethod
    def query(cls, cql, page=None):
        if cls.q:
            return cls.q.query(cql, page)
        else:
            return None, 0, None #rows, query_time, page_state

app = Flask(__name__, template_folder='view')

# app.config['SECRET_KEY'] = os.urandom(24) # 等同于 app.secret_key = os.urandom(24)
app.config['SECRET_KEY'] = 'dev'
app.config['SEND_FILE_MAX_AGE_DEFAULT'] = timedelta(seconds=1)
# class DBView(views.View):
#     def dispatch_request(self):
#         return jsonify('')

# app.add_url_rule('/db', view_func=DBView.as_view('dbview'))

@app.context_processor
def global_data():
    rows = []
    keyspaces = set()
    tables = []
    cql = ""

    try:
        rows, tm, page = DB.query('SELECT keyspace_name, table_name FROM system_schema.tables')
    except Exception as e:
        flash('Error: %s' %str(e))
        return dict()

    if not rows:
        rows = []
    for row in rows:
        if not row['keyspace_name'].startswith('system'):
            keyspaces.add(row['keyspace_name'])
            tables.append(row['table_name'])
    return dict(query_time=tm, keyspaces=keyspaces, tables=tables, cql=cql)

@app.template_global()
def list_without_last(li):
    length = len(list(li))
    if length > 0:
        return li[:length - 1]
    return li

#@app.route('/', methods=['GET'])
@app.route('/')
def main():
    return render_template('login.html', page_title='Cassandra DB')

@app.route('/db', methods=['GET', 'POST'])
def db():
    rows = []
    keyspaces = set()
    tables = []
    if request.method == 'POST':
        ip = request.form.get('ip')
        port = request.form.get('port')
        user = request.form.get('user')
        password = request.form.get('password')
        ssh = request.form.get('ssh')
        ssh_ip = request.form.get('ssh_ip')
        ssh_user = request.form.get('ssh_user')
        ssh_password = request.form.get('ssh_password')

        if ssh and not (ssh_ip and ssh_user and ssh_password):
            flash('Please input ssh information.')
            return redirect(url_for('main'))

        if ip and port and user and password:
            DB.init(ip, port, user, password)
            if ssh:
                ret = DB.ssh(ssh_ip, ssh_user, ssh_password)
                if ret:
                    flash('Error: %s' %ret)
                    return redirect(url_for('main'))

    return render_template('db.html')

@app.route('/db/query', methods=['POST'])
def query():
    paging = None
    disconnect = request.form.get('disconnect')
    if disconnect:
        DB.close()
        return redirect(url_for('main'))

    cql = request.form.get('cql')
    if not cql:
        return redirect(url_for('main'))

    if request.form.get('next'):
        paging = session.get('page')
    rows, tm, page = DB.query(cql, paging)
    session['page'] = page
    if not rows:
        rows = []
    return render_template('db.html', page=page, cql=cql, query_time=tm, rows=rows)

@app.route('/db/edit/<int:key>', methods=['GET', 'POST'])
def edit(key):
    row = {}
    if request.method == 'POST':
        flash('Item Updated')
        return redirect(url_for('db'))
    return render_template('edit.html', row=row)

@app.route('/db/delete/<int:key>', methods=['POST'])
def delete(key):
    row = {}
    return redirect(url_for('db'))

@app.errorhandler(404)
def not_found(error):
    return make_response(jsonify({'error': 'Not found'}), 404)

if __name__ == '__main__':
    app.run(host="0.0.0.0", port=80, debug=True)