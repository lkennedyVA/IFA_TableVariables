USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspRCRPSetDelete
	CreatedBy: Larry Dugger
	Date: 2016-07-06
	Descr: This procedure will delete the associated records, unless they are currently
	used by another R.C.
   
	Functions: [error].[uspLogErrorDetailInsertOut]

	History:
		2016-07-06 - LBD - Created, always follow this by executing
			[riskprocessing].[uspLadderRungCondensedBuild] and
			[riskprocessing].[uspRCLadderRungCondensedBuild]
*****************************************************************************************/
ALTER PROCEDURE [riskprocessing].[uspRCRPSetDelete](
    @pnvRCCollectionName nvarchar(100)
)
AS
BEGIN
   SET NOCOUNT ON;

   	DECLARE @MarkedForDeletion table (
		 Id int
		,[Type] nvarchar(100)
	); 

	DECLARE @iId int 
		,@iErrorDetailId int
		,@iCurrentTransactionLevel int
		,@sSchemaName sysname;
	SET @sSchemaName = N'riskprocessing';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;

   	INSERT INTO @MarkedForDeletion(Id,[Type])
	SELECT DISTINCT Id,[Type]
	FROM [riskprocessing].[ufnRcRpSet](@pnvRCCollectionName) n
	WHERE NOT EXISTS (SELECT 'X' FROM [riskprocessing].[ufnNotRcRpSet](@pnvRCCollectionName) 
						WHERE n.Id = Id AND n.[Type] = [Type]);
	IF @@ROWCOUNT > 0
	BEGIN
		--RCLadderTop
		DECLARE csrRC CURSOR FOR
		SELECT Id
		FROM @MarkedForDeletion
		WHERE [Type] = 'RC';
		OPEN csrRC
		FETCH csrRC INTO @iId;
		WHILE @@FETCH_STATUS = 0
		BEGIN
			EXECUTE [riskprocessing].[uspRCLadderTopDeactivateOut] @piRCLadderTopId=@iId, @pnvUserName='System';
			FETCH csrRC INTO @iId;
		END
		CLOSE csrRC
		DEALLOCATE csrRC
		--LadderTopXref
		DECLARE csrLTX CURSOR FOR
		SELECT Id
		FROM @MarkedForDeletion
		WHERE [Type] in ('RC LSLTX','RC LCLTX');
		OPEN csrLTX
		FETCH csrLTX INTO @iId;
		WHILE @@FETCH_STATUS = 0
		BEGIN
			EXECUTE [riskprocessing].[uspLadderTopXrefDeactivateOut] @piLadderTopXrefId=@iId, @pnvUserName='System';
			FETCH csrLTX INTO @iId;
		END
		CLOSE csrLTX
		DEALLOCATE csrLTX
		--LadderTop
		DECLARE csrRP CURSOR FOR
		SELECT Id
		FROM @MarkedForDeletion
		WHERE [Type] = 'RP';
		OPEN csrRP
		FETCH csrRP INTO @iId;
		WHILE @@FETCH_STATUS = 0
		BEGIN
			EXECUTE [riskprocessing].[uspLadderTopDeactivateOut] @piLadderTopId=@iId, @pnvUserName='System';
			FETCH csrRP INTO @iId;
		END
		CLOSE csrRP
		DEALLOCATE csrRP
		--LadderDBProcessXref
		DECLARE csrLDBPX CURSOR FOR
		SELECT Id
		FROM @MarkedForDeletion
		WHERE [Type] in ('RP SLDBPX','RP CLDBPX');
		OPEN csrLDBPX
		FETCH csrLDBPX INTO @iId;
		WHILE @@FETCH_STATUS = 0
		BEGIN
			EXECUTE [riskprocessing].[uspLadderDBProcessXrefDeactivateOut] @piLadderDBprocessXrefId=@iId, @pnvUserName='System';
			FETCH csrLDBPX INTO @iId;
		END
		CLOSE csrLDBPX
		DEALLOCATE csrLDBPX
	END
END
