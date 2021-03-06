{Pool} = require 'generic-pool'
tds = require 'tedious'
util = require 'util'

{TYPES, declare, cast} = require './datatypes'
DECLARATIONS = require('./datatypes').DECLARATIONS
UDT = require('./udt').PARSERS
Table = require('./table')

###
@ignore
###

getTediousType = (type) ->
	switch type
		when TYPES.VarChar then return tds.TYPES.VarChar
		when TYPES.NVarChar then return tds.TYPES.NVarChar
		when TYPES.Text then return tds.TYPES.Text
		when TYPES.Int then return tds.TYPES.Int
		when TYPES.BigInt then return tds.TYPES.BigInt
		when TYPES.TinyInt then return tds.TYPES.TinyInt
		when TYPES.SmallInt then return tds.TYPES.SmallInt
		when TYPES.Bit then return tds.TYPES.Bit
		when TYPES.Float then return tds.TYPES.Float
		when TYPES.Decimal then return tds.TYPES.Decimal
		when TYPES.Numeric then return tds.TYPES.Numeric
		when TYPES.Real then return tds.TYPES.Real
		when TYPES.Money then return tds.TYPES.Money
		when TYPES.SmallMoney then return tds.TYPES.SmallMoney
		when TYPES.Time then return tds.TYPES.TimeN
		when TYPES.Date then return tds.TYPES.DateN
		when TYPES.DateTime then return tds.TYPES.DateTime
		when TYPES.DateTime2 then return tds.TYPES.DateTime2N
		when TYPES.DateTimeOffset then return tds.TYPES.DateTimeOffsetN
		when TYPES.SmallDateTime then return tds.TYPES.SmallDateTime
		when TYPES.UniqueIdentifier then return tds.TYPES.UniqueIdentifierN
		when TYPES.Xml then return tds.TYPES.VarChar
		when TYPES.Char then return tds.TYPES.VarChar
		when TYPES.NChar then return tds.TYPES.NVarChar
		when TYPES.NText then return tds.TYPES.NVarChar
		when TYPES.Image then return tds.TYPES.Image
		when TYPES.Binary then return tds.TYPES.Binary
		when TYPES.VarBinary then return tds.TYPES.VarBinary
		when TYPES.UDT, TYPES.Geography, TYPES.Geometry then return tds.TYPES.UDT
		when TYPES.TVP then return tds.TYPES.TVP
		else return type

###
@ignore
###

getMssqlType = (type) ->
	switch type
		when tds.TYPES.Char then return TYPES.Char
		when tds.TYPES.NChar then return TYPES.NChar
		when tds.TYPES.VarChar then return TYPES.VarChar
		when tds.TYPES.NVarChar then return TYPES.NVarChar
		when tds.TYPES.Text then return TYPES.Text
		when tds.TYPES.NText then return TYPES.NText
		when tds.TYPES.Int, tds.TYPES.IntN then return TYPES.Int
		when tds.TYPES.BigInt then return TYPES.BigInt
		when tds.TYPES.TinyInt then return TYPES.TinyInt
		when tds.TYPES.SmallInt then return TYPES.SmallInt
		when tds.TYPES.Bit, tds.TYPES.BitN then return TYPES.Bit
		when tds.TYPES.Float, tds.TYPES.FloatN then return TYPES.Float
		when tds.TYPES.Real then return TYPES.Real
		when tds.TYPES.Money, tds.TYPES.MoneyN then return TYPES.Money
		when tds.TYPES.SmallMoney then return TYPES.SmallMoney
		when tds.TYPES.Numeric, tds.TYPES.NumericN then return TYPES.Numeric
		when tds.TYPES.Decimal, tds.TYPES.DecimalN then return TYPES.Decimal
		when tds.TYPES.DateTime, tds.TYPES.DateTimeN then return TYPES.DateTime
		when tds.TYPES.TimeN then return TYPES.Time
		when tds.TYPES.DateN then return TYPES.Date
		when tds.TYPES.DateTime2N then return TYPES.DateTime2
		when tds.TYPES.DateTimeOffsetN then return TYPES.DateTimeOffset
		when tds.TYPES.SmallDateTime then return TYPES.SmallDateTime
		when tds.TYPES.UniqueIdentifierN then return TYPES.UniqueIdentifier
		when tds.TYPES.Image then return TYPES.Image
		when tds.TYPES.Binary then return TYPES.Binary
		when tds.TYPES.VarBinary then return TYPES.VarBinary
		when tds.TYPES.Xml then return TYPES.Xml
		when tds.TYPES.UDT then return TYPES.UDT
		when tds.TYPES.TVP then return TYPES.TVP

###
@ignore
###

createColumns = (metadata) ->
	out = {}
	for column, index in metadata
		out[column.colName] =
			index: index
			name: column.colName
			length: column.dataLength
			type: getMssqlType(column.type)
			scale: column.scale
			precision: column.precision
		
		if column.udtInfo?
			out[column.colName].udt =
				name: column.udtInfo.typeName
				database: column.udtInfo.dbname
				schema: column.udtInfo.owningSchema
				assembly: column.udtInfo.assemblyName
			
			if DECLARATIONS[column.udtInfo.typeName]
				out[column.colName].type = DECLARATIONS[column.udtInfo.typeName]
	
	out

###
@ignore
###

valueCorrection = (value, metadata) ->
	if metadata.type is tds.TYPES.UDT and value?
		if UDT[metadata.udtInfo.typeName]
			UDT[metadata.udtInfo.typeName] value
			
		else
			value
		
	else
		value

###
@ignore
###

parameterCorrection = (value) ->
	if value instanceof Table
		tvp =
			columns: []
			rows: value.rows
			
		for col in value.columns
			tvp.columns.push
				name: col.name
				type: getTediousType col.type
				length: col.length
				scale: col.scale
				precision: col.precision
			
		tvp
			
	else
		value

###
@ignore
###

module.exports = (Connection, Transaction, Request, ConnectionError, TransactionError, RequestError) ->
	class TediousConnection extends Connection
		pool: null
		
		connect: (config, callback) ->
			cfg =
				userName: config.user
				password: config.password
				server: config.server
				options: config.options
				domain: config.domain
			
			cfg.options.database ?= config.database
			cfg.options.port ?= config.port
			cfg.options.connectTimeout ?= config.connectionTimeout ? config.timeout ? 15000 # config.timeout deprecated in 0.6.0
			cfg.options.requestTimeout ?= config.requestTimeout ? 15000
			cfg.options.tdsVersion ?= '7_4'
			cfg.options.rowCollectionOnDone = false
			cfg.options.rowCollectionOnRequestCompletion = false
			cfg.options.useColumnNames = false
			cfg.options.appName ?= 'node-mssql'
			
			# tedious always connect via tcp when port is specified
			if cfg.options.instanceName then delete cfg.options.port
			
			if config.debug
				cfg.options.debug =
					packet: true
					token: true
					data: true
					payload: true

			cfg_pool =
				name: 'mssql'
				max: 10
				min: 0
				idleTimeoutMillis: 30000
				create: (callback) =>
					c = new tds.Connection cfg

					c.once 'connect', (err) ->
						if err then err = ConnectionError err
						if err then return callback err, null # there must be a second argument null
						callback null, c
					
					c.on 'error', (err) =>
						@emit 'error', err
					
					if config.debug
						c.on 'debug', (msg) => @_debug msg

				validate: (c) ->
					c? and !c.closed
				
				destroy: (c) ->
					c?.close()
			
			if config.pool
				for key, value of config.pool
					cfg_pool[key] = value

			@pool = Pool cfg_pool, cfg
			
			#create one testing connection to check if everything is ok
			@pool.acquire (err, connection) =>
				# and release it immediately
				@pool.release connection
				
				if err
					@pool.destroyAllNow()
					@pool = null

				callback err
		
		close: (callback) ->
			unless @pool then return callback null
			
			@pool.drain =>
				@pool.destroyAllNow()
				@pool = null
				callback null
	
	class TediousTransaction extends Transaction
		begin: (callback) ->
			@connection.pool.acquire (err, connection) =>
				if err then return callback err
				
				@_pooledConnection = connection
				connection.beginTransaction (err) =>
					if err then err = TransactionError err
					callback err
				
				, @name, @isolationLevel
			
		commit: (callback) ->
			@_pooledConnection.commitTransaction (err) =>
				if err then err = TransactionError err
				
				@connection.pool.release @_pooledConnection
				@_pooledConnection = null
				
				callback err

		rollback: (callback) ->
			@_pooledConnection.rollbackTransaction (err) =>
				if err then err = TransactionError err
				
				@connection.pool.release @_pooledConnection
				@_pooledConnection = null
				
				callback err
		
	class TediousRequest extends Request
		###
		Execute specified sql batch.
		###
		
		batch: (batch, callback) ->
			@_batch = true
			TediousRequest::query.call @, batch, callback
		
		###
		Execute specified sql command.
		###

		query: (command, callback) ->
			columns = {}
			recordset = []
			recordsets = []
			started = Date.now()
			errors = []
			batchLastRow = null
			batchHasOutput = false
			handleError = (err) =>
				e = new RequestError err.message, 'EREQUEST'
				
				if @stream
					@emit 'error', e
				
				# we must collect errors even in stream mode
				errors.push e
			
			@_acquire (err, connection) =>
				unless err
					if @verbose then @_log "---------- sql #{if @_batch then 'batch' else 'query'} ----------\n    #{if @_batch then 'batch' else 'query'}: #{command}"

					if @canceled
						if @verbose then @_log "---------- canceling ----------"
						@_release connection
						return callback? new RequestError "Canceled.", 'ECANCEL'
					
					@_cancel = =>
						if @verbose then @_log "---------- canceling ----------"
						connection.cancel()
					
					# attach handler to handle multiple error messages
					connection.on 'errorMessage', handleError
					
					req = new tds.Request command, (err) =>
						# to make sure we handle no-sql errors as well
						if err and err.message isnt errors[errors.length - 1]?.message
							err = RequestError err
							
							if @stream
								@emit 'error', err
							
							errors.push err
						
						# process batch outputs
						if batchHasOutput
							unless @stream
								batchLastRow = recordsets.pop()[0]
							
							for name, value of batchLastRow when name isnt '___return___'
								if @verbose
									if value is tds.TYPES.Null
										@_log "   output: @#{name}, null"
									else
										@_log "   output: @#{name}, #{@parameters[name].type.declaration.toLowerCase()}, #{value}"
								
								@parameters[name].value = if value is tds.TYPES.Null then null else value
						
						if @verbose 
							if errors.length
								@_log "    error: #{error}" for error in errors
							
							elapsed = Date.now() - started
							@_log " duration: #{elapsed}ms"
							@_log "---------- completed ----------"

						@_cancel = null
						
						if errors.length and not @stream
							error = errors.pop()
							error.precedingErrors = errors
						
						connection.removeListener 'errorMessage', handleError
						@_release connection
						
						if @stream
							callback null, null
						
						else
							callback? error, if @multiple then recordsets else recordsets[0]
					
					req.on 'columnMetadata', (metadata) =>
						columns = createColumns metadata
						
						if @stream
							if @_batch
								# don't stream recordset with output values in batches
								unless columns["___return___"]?
									@emit 'recordset', columns
							
							else
								@emit 'recordset', columns

					doneHandler = (rowCount, more, rows) =>
						# this function is called even when select only set variables so we should skip adding a new recordset
						if Object.keys(columns).length is 0 then return

						unless @stream
							# all rows of current recordset loaded
							Object.defineProperty recordset, 'columns', 
								enumerable: false
								value: columns
								
							Object.defineProperty recordset, 'toTable', 
								enumerable: false
								value: -> Table.fromRecordset @
								
							recordsets.push recordset
							
						recordset = []
						columns = {}
					
					req.on 'doneInProc', doneHandler # doneInProc handlers are used in both queries and batches
					req.on 'done', doneHandler # done handlers are used in batches
					
					req.on 'returnValue', (parameterName, value, metadata) =>
						if @verbose
							if value is tds.TYPES.Null
								@_log "   output: @#{parameterName}, null"
							else
								@_log "   output: @#{parameterName}, #{@parameters[parameterName].type.declaration.toLowerCase()}, #{value}"
								
						@parameters[parameterName].value = if value is tds.TYPES.Null then null else value
					
					req.on 'row', (columns) =>
						unless recordset
							recordset = []
							
						row = {}
						for col in columns
							col.value = valueCorrection col.value, col.metadata
							
							exi = row[col.metadata.colName]
							if exi?
								if exi instanceof Array
									exi.push col.value
									
								else
									row[col.metadata.colName] = [exi, col.value]
							
							else
								row[col.metadata.colName] = col.value
						
						if @verbose
							@_log util.inspect(row)
							@_log "---------- --------------------"
						
						if @stream
							if @_batch
								# dont stream recordset with output values in batches
								if row["___return___"]?
									batchLastRow = row
								
								else
									@emit 'row', row
							
							else
								@emit 'row', row
							
						else
							recordset.push row
					
					if @_batch
						if Object.keys(@parameters).length
							declarations = ("@#{name} #{declare(param.type, param)}" for name, param of @parameters)
							assigns = ("@#{name} = #{cast(param.value, param.type, param)}" for name, param of @parameters)
							selects = ("@#{name} as [#{name}]" for name, param of @parameters when param.io is 2)
							batchHasOutput = selects.length > 0
							
							req.sqlTextOrProcedure = "declare #{declarations.join(', ')};select #{assigns.join(', ')};#{req.sqlTextOrProcedure};#{if batchHasOutput then ('select 1 as [___return___], '+ selects.join(', ')) else ''}"
					
					else
						for name, param of @parameters
							if @verbose
								if param.value is tds.TYPES.Null
									@_log "   #{if param.io is 1 then " input" else "output"}: @#{param.name}, null"
								else
									@_log "   #{if param.io is 1 then " input" else "output"}: @#{param.name}, #{param.type.declaration.toLowerCase()}, #{param.value}"
							
							if param.io is 1
								req.addParameter param.name, getTediousType(param.type), parameterCorrection(param.value), {length: param.length, scale: param.scale, precision: param.precision}
							else
								req.addOutputParameter param.name, getTediousType(param.type), parameterCorrection(param.value), {length: param.length, scale: param.scale, precision: param.precision}
					
					if @verbose then @_log "---------- response -----------"
					connection[if @_batch then 'execSqlBatch' else 'execSql'] req
				
				else
					if connection then @_release connection
					callback? err
					
		###
		Execute stored procedure with specified parameters.
		###
		
		execute: (procedure, callback) ->
			columns = {}
			recordset = []
			recordsets = []
			returnValue = 0
			started = Date.now()
			errors = []
			handleError = (err) =>
				e = new RequestError err.message, 'EREQUEST'
				
				if @stream
					@emit 'error', e
				
				# we must collect errors even in stream mode
				errors.push e

			@_acquire (err, connection) =>
				unless err
					if @verbose then @_log "---------- sql execute --------\n     proc: #{procedure}"
					
					if @canceled
						if @verbose then @_log "---------- canceling ----------"
						@_release connection
						return callback? new RequestError "Canceled.", 'ECANCEL'
					
					@_cancel = =>
						if @verbose then @_log "---------- canceling ----------"
						connection.cancel()
					
					# attach handler to handle multiple error messages
					connection.on 'errorMessage', handleError
					
					req = new tds.Request procedure, (err) =>
						# to make sure we handle no-sql errors as well
						if err and err.message isnt errors[errors.length - 1]?.message
							err = RequestError err
							
							if @stream
								@emit 'error', err
							
							errors.push err
						
						if @verbose 
							if errors.length
								@_log "    error: #{error}" for error in errors
							
							elapsed = Date.now() - started
							@_log "   return: #{returnValue}"
							@_log " duration: #{elapsed}ms"
							@_log "---------- completed ----------"
						
						@_cancel = null
						
						if errors.length and not @stream
							error = errors.pop()
							error.precedingErrors = errors
						
						connection.removeListener 'errorMessage', handleError
						@_release connection
						
						if @stream
							callback null, null, returnValue
						
						else
							recordsets.returnValue = returnValue
							callback? error, recordsets, returnValue
					
					req.on 'columnMetadata', (metadata) =>
						columns = createColumns metadata
						
						if @stream
							@emit 'recordset', columns
					
					req.on 'row', (columns) =>
						unless recordset
							recordset = []
							
						row = {}
						for col in columns
							col.value = valueCorrection col.value, col.metadata
							
							exi = row[col.metadata.colName]
							if exi?
								if exi instanceof Array
									exi.push col.value
									
								else
									row[col.metadata.colName] = [exi, col.value]
							
							else
								row[col.metadata.colName] = col.value
						
						if @verbose
							@_log util.inspect(row)
							@_log "---------- --------------------"
						
						if @stream
							@emit 'row', row
						
						else
							recordset.push row
					
					req.on 'doneInProc', (rowCount, more, rows) =>
						# filter empty recordsets when NOCOUNT is OFF
						if Object.keys(columns).length is 0 then return
						
						unless @stream
							# all rows of current recordset loaded
							Object.defineProperty recordset, 'columns', 
								enumerable: false
								value: columns
								
							Object.defineProperty recordset, 'toTable', 
								enumerable: false
								value: -> Table.fromRecordset @
							
							recordsets.push recordset
							
						recordset = []
						columns = {}
					
					req.on 'doneProc', (rowCount, more, returnStatus, rows) =>
						returnValue = returnStatus
					
					req.on 'returnValue', (parameterName, value, metadata) =>
						if @verbose
							if value is tds.TYPES.Null
								@_log "   output: @#{parameterName}, null"
							else
								@_log "   output: @#{parameterName}, #{@parameters[parameterName].type.declaration.toLowerCase()}, #{value}"
								
						@parameters[parameterName].value = if value is tds.TYPES.Null then null else value
					
					for name, param of @parameters
						if @verbose
							if param.value is tds.TYPES.Null
								@_log "   #{if param.io is 1 then " input" else "output"}: @#{param.name}, null"
							else
								@_log "   #{if param.io is 1 then " input" else "output"}: @#{param.name}, #{param.type.declaration.toLowerCase()}, #{param.value}"
						
						if param.io is 1
							req.addParameter param.name, getTediousType(param.type), parameterCorrection(param.value), {length: param.length, scale: param.scale, precision: param.precision}
						else
							req.addOutputParameter param.name, getTediousType(param.type), parameterCorrection(param.value), {length: param.length, scale: param.scale, precision: param.precision}

					if @verbose then @_log "---------- response -----------"
					connection.callProcedure req
				
				else
					if connection then @_release connection
					callback? err
				
		###
		Cancel currently executed request.
		###
		
		cancel: ->
			if @_cancel then return @_cancel()
			true
		
	return {
		Connection: TediousConnection
		Transaction: TediousTransaction
		Request: TediousRequest
		fix: -> # there is nothing to fix in this driver
	}
