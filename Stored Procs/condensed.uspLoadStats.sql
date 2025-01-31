USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/*******************************************************************
	Name: [condensed].[uspLoadStats]
	Created By: Larry Dugger
	Description: Procedure to resynch the following condensed tables
		REMEMBER if any indexes are added to these tables, 
		THIS PROCEDURE MUST BE UPDATED.
 	 
	Tables: [Condensed].[stat].[DollarStrat]
		,[Condensed].[stat].[OnUsAccount]
		,[Condensed].[stat].[OnUsRouting]
		,[Condensed].[stat].[PayerRtnAcctNumLenVol]
		,[Condensed].[stat].[PayerRtnVolume]
		,[Condensed].[new].[DollarStrat]
		,[Condensed].[new].[OnUsAccount]
		,[Condensed].[new].[OnUsRouting]
		,[Condensed].[new].[PayerRtnAcctNumLenVol]
		,[Condensed].[stat].[NewPayerRtnVolume]

	History:
		2017-02-15 - LBD - Created
		2017-02-23 - LBD - Modified, deleting KCP records with ValidFICustomerId = 0
			or ValidFIPayerId = 0
		2017-05-11 - LBD - Modified, adjusted CIX to use OrgId
		2017-05-16 - LBD - Modified, adjusted to log timing
		2017-06-28 - LBD - Modified, adjusted to reduce contention on reference tables 
			CustomerIdXref and Payer.
			Added table reads to help after rename.
		2017-07-06 - LBD - Modified, adjusted to update newKCP before renaming any tables.
		2017-07-11 - LBD - Modified, added new index for Customer
		2017-07-15 - LBD - Modified, enhanced buffer loading.
		2017-07-19 - LBD - Modified, restructured to perform easy update of NewKCP
			,prior to renaming any table. 
		2017-07-26 - LBD - Modified, isolated all index creation, so if they error we exit
		2017-08-03 - LBD - Modified, converted to new timing procedure, adjusted message lengths
		2017-08-11 - LBD - Modified, changed the comparison to < (see end of proc)
		2017-09-13 - LBD - Modified, double check when inserting that we aren't inserting duplicates....
		2017-11-29 - LBD - Modified, adjusted to immediately write IFATiming data.
		2018-02-17 - LBD - Modified, adjusted method to insert CIX records, 
			correct any questionable code
		2018-02-21 - LBD - Modified, corrected the use of Paging
		2018-08-07 - LBD - Modified, removed the tempoary tables loads....
		2018-08-14 - LBD - Modified, remove from NewPayer, where the Id is Null, after all the
			update\insert are performed (due to the time it takes to perform)
		2018-08-16 - LBD - Modified, using partition switching instead of renaming.
		2019-03-21 - LBD - Modified, OnUsAccount UX not necessary
		2019-04-13 - LBD - Modified, changed 'return' to throw
		2019-07-02 - LBD - Modified, adjusted to not Insert CIX when the CustomerId is null
		2019-08-03 - LBD - Modified, commented out all activity associated with
		 the Customer, Payer, and KCP tables
		2019-11-13 - LBD - Modified, removed references in table list, that aren't used
			along with commented-out old code
		2019-11-19 - LBD - Modified, added in support for new OnUsAccount ux
		2020-06-03 - LBD - Adjusted logging so it operates without locking (unless necessary)
*****************************************************************************************/
ALTER PROCEDURE [condensed].[uspLoadStats]
AS
BEGIN
	DECLARE @tblIFATiming [dbo].[IFATimingType];
	DECLARE @ncProcessKey nchar(25) = REPLACE(REPLACE(REPLACE(REPLACE(CONVERT(nvarchar(50),sysdatetime(),121),'-',''),' ',''),':',''),'.','');
	DECLARE @iLogLevel int = ISNULL(TRY_CONVERT(INT,[common].[ufnConfigValue](N'LogLevel [condensed].[uspLoadStats]')),1)
		,@dtTimerDate datetime2(7) = SYSDATETIME()
		,@dtInitial datetime2(7) = SYSDATETIME() --used for complete time in procedure
		,@ncSchemaName nchar(20) = N'condensed'
		,@ncObjectName nchar(50) = N'uspLoadStats';

	DECLARE @bEnableTimer bit = 1
		,@iErrorDetailId INT
		,@sSchemaName nvarchar(128) = 'condensed';

	IF @iLogLevel > 0
	BEGIN
		INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
		VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Enter' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME()); 
		SET @dtTimerDate = SYSDATETIME()
	END

	--TABLE SWITCHING
	BEGIN TRY
		--Let the Renaming Begin, these tables need no updates, just replacements
		--SWITCH New and Current DollarStrat
		IF [condensed].[ufnTableExists](N'[stat].[DollarStrat]') = 1
			AND [condensed].[ufnTableExists](N'[new].[DollarStrat]') = 1
		BEGIN
			BEGIN TRAN
				--Anyone who tries to query the table after the switch has happened and before
				--the transaction commits will be blocked: we've got a schema mod lock on the table

				--cycle out Current DollarStrat
				ALTER TABLE [Condensed].[stat].[DollarStrat] SWITCH PARTITION 1 TO [Condensed].[old].[DollarStrat] PARTITION 1
					WITH ( WAIT_AT_LOW_PRIORITY ( MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = BLOCKERS ));  

				--Cycle in New DollarStrat
				ALTER TABLE [Condensed].[new].[DollarStrat] SWITCH PARTITION 1 TO [Condensed].[stat].[DollarStrat] PARTITION 1
					WITH ( WAIT_AT_LOW_PRIORITY ( MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = BLOCKERS ));

				-- Cycle Old to New
				ALTER TABLE [Condensed].[old].[DollarStrat] SWITCH PARTITION 1 TO [Condensed].[new].[DollarStrat] PARTITION 1
					WITH ( WAIT_AT_LOW_PRIORITY ( MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = BLOCKERS ));  
			COMMIT

			IF @iLogLevel > 0
			BEGIN
				INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
				VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Switched DollarStrat',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());  
				SET @dtTimerDate  = SYSDATETIME();
			END

			--SWITCH New and Current OnUsAccount
			IF [condensed].[ufnTableExists](N'[stat].[OnUsAccount]') = 1
				AND [condensed].[ufnTableExists](N'[new].[OnUsAccount]') = 1
			BEGIN
				--create special index before renaming
				EXEC [condensed].[uspCreateDropIndex] @pbCreate=1,@pnvTargetTable='new.OnUsAccount',@pnvTargetIndex='uxOnUsAccount',@piErrorDetailId=@iErrorDetailId OUTPUT;
				IF @iErrorDetailId <> 0 
					RETURN

				IF @iLogLevel > 0
				BEGIN
					INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
					VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Add new.OnUsAccount index',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());  
					SET @dtTimerDate  = SYSDATETIME();
				END

				BEGIN TRAN
					--Anyone who tries to query the table after the switch has happened and before
					--the transaction commits will be blocked: we've got a schema mod lock on the table

					--cycle out Current OnUsAccount
					ALTER TABLE [Condensed].[stat].[OnUsAccount] SWITCH PARTITION 1 TO [Condensed].[old].[OnUsAccount] PARTITION 1
						WITH ( WAIT_AT_LOW_PRIORITY ( MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = BLOCKERS ));  

					--Cycle in New OnUsAccount
					ALTER TABLE [Condensed].[new].[OnUsAccount] SWITCH PARTITION 1 TO [Condensed].[stat].[OnUsAccount] PARTITION 1
						WITH ( WAIT_AT_LOW_PRIORITY ( MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = BLOCKERS ));

					-- Cycle Old to New
					ALTER TABLE [Condensed].[old].[OnUsAccount] SWITCH PARTITION 1 TO [Condensed].[new].[OnUsAccount] PARTITION 1
						WITH ( WAIT_AT_LOW_PRIORITY ( MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = BLOCKERS ));  
				COMMIT

				IF @iLogLevel > 0
				BEGIN
					INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
					VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Switched OnUsAccount',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());  
					SET @dtTimerDate  = SYSDATETIME();
				END

				--delete special index before next load
				EXEC [condensed].[uspCreateDropIndex] @pbCreate=0,@pnvTargetTable='new.OnUsAccount',@pnvTargetIndex='uxOnUsAccount',@piErrorDetailId=@iErrorDetailId OUTPUT;
				IF @iErrorDetailId <> 0 
					RETURN

				IF @iLogLevel > 0
				BEGIN
					INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
					VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Drop new.OnUsAccount index',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());  
					SET @dtTimerDate  = SYSDATETIME();
				END

				--SWITCH New and Current OnUsRouting
				IF [condensed].[ufnTableExists](N'[stat].[OnUsRouting]') = 1
					AND [condensed].[ufnTableExists](N'[new].[OnUsRouting]') = 1
				BEGIN
					BEGIN TRAN
						--Anyone who tries to query the table after the switch has happened and before
						--the transaction commits will be blocked: we've got a schema mod lock on the table

						--cycle out Current OnUsRouting
						ALTER TABLE [Condensed].[stat].[OnUsRouting] SWITCH PARTITION 1 TO [Condensed].[old].[OnUsRouting] PARTITION 1
							WITH ( WAIT_AT_LOW_PRIORITY ( MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = BLOCKERS ));  

						--Cycle in New OnUsRouting
						ALTER TABLE [Condensed].[new].[OnUsRouting] SWITCH PARTITION 1 TO [Condensed].[stat].[OnUsRouting] PARTITION 1
							WITH ( WAIT_AT_LOW_PRIORITY ( MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = BLOCKERS ));

						-- Cycle Old to New
						ALTER TABLE [Condensed].[old].[OnUsRouting] SWITCH PARTITION 1 TO [Condensed].[new].[OnUsRouting] PARTITION 1
							WITH ( WAIT_AT_LOW_PRIORITY ( MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = BLOCKERS ));  
					COMMIT

					IF @iLogLevel > 0
					BEGIN
						INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
						VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Switched OnUsRouting',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());  
						SET @dtTimerDate  = SYSDATETIME();
					END
					--SWITCH New and Current PayerRtnAcctNumLenVol
					IF [condensed].[ufnTableExists](N'[stat].[PayerRtnAcctNumLenVol]') = 1
						AND [condensed].[ufnTableExists](N'[new].[PayerRtnAcctNumLenVol]') = 1
					BEGIN
						BEGIN TRAN
							--Anyone who tries to query the table after the switch has happened and before
							--the transaction commits will be blocked: we've got a schema mod lock on the table

							--cycle out Current PayerRtnAcctNumLenVol
							ALTER TABLE [Condensed].[stat].[PayerRtnAcctNumLenVol] SWITCH PARTITION 1 TO [Condensed].[old].[PayerRtnAcctNumLenVol] PARTITION 1
								WITH ( WAIT_AT_LOW_PRIORITY ( MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = BLOCKERS ));  

							--Cycle in New PayerRtnAcctNumLenVol
							ALTER TABLE [Condensed].[new].[PayerRtnAcctNumLenVol] SWITCH PARTITION 1 TO [Condensed].[stat].[PayerRtnAcctNumLenVol] PARTITION 1
								WITH ( WAIT_AT_LOW_PRIORITY ( MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = BLOCKERS ));

							-- Cycle Old to New
							ALTER TABLE [Condensed].[old].[PayerRtnAcctNumLenVol] SWITCH PARTITION 1 TO [Condensed].[new].[PayerRtnAcctNumLenVol] PARTITION 1
								WITH ( WAIT_AT_LOW_PRIORITY ( MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = BLOCKERS ));  
						COMMIT

						IF @iLogLevel > 0
						BEGIN
							INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
							VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Switched PayerRtnAcctNumLenVol',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());  
							SET @dtTimerDate  = SYSDATETIME();
						END

						--SWITCH New and Current PayerRtnVolume
						IF [condensed].[ufnTableExists](N'[stat].[PayerRtnVolume]') = 1
							AND [condensed].[ufnTableExists](N'[new].[PayerRtnVolume]') = 1
						BEGIN
							BEGIN TRAN
								--Anyone who tries to query the table after the switch has happened and before
								--the transaction commits will be blocked: we've got a schema mod lock on the table

								--cycle out Current PayerRtnVolume
								ALTER TABLE [Condensed].[stat].[PayerRtnVolume] SWITCH PARTITION 1 TO [Condensed].[old].[PayerRtnVolume] PARTITION 1
									WITH ( WAIT_AT_LOW_PRIORITY ( MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = BLOCKERS ));  

								--Cycle in New PayerRtnVolume
								ALTER TABLE [Condensed].[new].[PayerRtnVolume] SWITCH PARTITION 1 TO [Condensed].[stat].[PayerRtnVolume] PARTITION 1
									WITH ( WAIT_AT_LOW_PRIORITY ( MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = BLOCKERS ));

								-- Cycle Old to New
								ALTER TABLE [Condensed].[old].[PayerRtnVolume] SWITCH PARTITION 1 TO [Condensed].[new].[PayerRtnVolume] PARTITION 1
									WITH ( WAIT_AT_LOW_PRIORITY ( MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = BLOCKERS ));  
							COMMIT

							IF @iLogLevel > 0
							BEGIN
								INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
								VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Switched PayerRtnVolume',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());  
								SET @dtTimerDate  = SYSDATETIME();
							END								
						END
						ELSE --SWITCH New and Current PayerRtnVolume
						BEGIN
							INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
							VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'PayerRtnVolume Not Switched',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());  
							THROW 50000,N'PayerRtnVolume Not Switched',1;
						END
					END
					ELSE --SWITCH New and Current PayerRtnAcctNumLenVol
					BEGIN
						INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
						VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'PayerRtnAcctNumLenVol Not Switched',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());  
						THROW 50000,N'PayerRtnAcctNumLenVol Not Switched',1;
					END
				END
				ELSE --SWITCH New and Current OnUsRouting
				BEGIN
					INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
					VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'OnUsRouting Not Switched',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());  
					THROW 50000,N'OnUsRouting Not Switched',1;
				END
			END
			ELSE
			BEGIN
				INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
				VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'OnUsAccount Not Switched',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());  
				THROW 50000,N'OnUsAccount Not Switched',1;
			END
		END
		ELSE --SWITCH New and Current DollarStrat
		BEGIN
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'DollarStrat Not Switched',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
			THROW 50000,N'DollarStrat Not Switched',1;
		END
	END TRY
	BEGIN CATCH
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
		VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Exit-ErrorDetailId ='+CONVERT(NCHAR(10),@iErrorDetailId),DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());  		
		THROW
	END CATCH
	--ADJUSTED TO HANDLE THE RETURN LIMIT
	--Last Message uses @dtInitial
	IF @iLogLevel > 0
		INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
		VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Exit' 
			,CASE WHEN DATEDIFF(SECOND,@dtInitial,SYSDATETIME()) < 2147 --2017-08-11 LBD
				THEN DATEDIFF(microsecond,@dtInitial,SYSDATETIME())
				ELSE 0
			END
			,SYSDATETIME());  

END
