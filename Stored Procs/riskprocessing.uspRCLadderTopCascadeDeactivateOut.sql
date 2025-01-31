USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspRCLadderTopCascadeDeactivateOut
	CreatedBy: Larry Dugger
	Date: 2016-06-29
	Descr: This procedure will set the StatusFlag to 1 'InActive', and 
	cascade the change	to all the sub table records associated with this record.
	It is always good to execute [riskprocessing].[uspLadderRungCondensedBuild]
		and EXECUTE [riskprocessing].[uspRCLadderRungCondensedBuild]
		following, if you want it active to the system

	Tables: [riskprocessing].[RCLadderTop]
   
	Functions: [error].[uspLogErrorDetailInsertOut]
	Procedures: [riskprocessing].[uspLadderTopXrefDeactivateOut]
		,[riskprocessing].[uspLadderTopDeactivateOut]
		,[riskprocessing].[uspLadderDBProcessXrefDeactivateOut]

	History:
		2016-06-29 - LBD - Created.
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [riskprocessing].[uspRCLadderTopCascadeDeactivateOut](
	 @piRCLadderTopId INT OUTPUT
	,@pnvUserName NVARCHAR(100) = 'N/A'
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @RCLadderTop table (
		 RCLadderTopId int
		,RCId int
		,OrgXrefId int
		,LadderTopXrefId int
		,CollectionName nvarchar(100)
		,StatusFlag int
		,DateActivated datetime
		,UserName nvarchar(100));
	DECLARE @iXref int
		,@iPk int
		,@nvType nvarchar(6) 
		,@iErrorDetailId int
		,@iCurrentTransactionLevel int
		,@sSchemaName sysname;
	SET @sSchemaName = N'riskprocessing';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			UPDATE [riskprocessing].[RCLadderTop]
			SET StatusFlag = 0
				,DateActivated = SYSDATETIME()
				,UserName = @pnvUserName
			OUTPUT deleted.RCLadderTopId
				,deleted.RCId
				,deleted.OrgXrefId
				,deleted.LadderTopXrefId
				,deleted.CollectionName
				,deleted.StatusFlag
				,deleted.DateActivated
				,deleted.UserName
			INTO @RCLadderTop
			WHERE RCLadderTopId = @piRCLadderTopId;
			----Anytime an update occurs we place an original copy in an archive table
			--INSERT INTO [archive].[RCLadderTop](RCLadderTopId
			--	,RCId
			--	,OrgXrefId
			--	,LadderTopXrefId
			--	,CollectionName
			--	,StatusFlag
			--	,DateActivated
			--	,UserName
			--	,DateArchived
			--) 
			--SELECT RCLadderTopId
			--	,RCId
			--	,OrgXrefId
			--	,LadderTopXrefId
			--	,CollectionName
			--	,StatusFlag
			--	,DateActivated
			--	,UserName
			--	,SYSDATETIME()
			--FROM @RCLadderTop
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			SET @piRCLadderTopId = -1 * @iErrorDetailId; --return the errordetailid negative (indicates an error occurred)
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel
		BEGIN
			COMMIT TRANSACTION;
			DECLARE csr_deactivate CURSOR FOR
			WITH Cte (Xref,Pk,[Type])
			AS (
			SELECT rclrc.LadderTopXrefId, rclrc.LadderTopId, CONVERT(NVARCHAR(6),'Ladder')
			FROM [condensed].[RCLadderRungCondensed] rclrc
			INNER JOIN @RCLadderTop rclt on rclrc.RCLadderTopId = rclt.RCLadderTopId
			UNION ALL
			SELECT lrc.LadderDBProcessXrefId, 0, CONVERT(NVARCHAR(6),'Rung')
			FROM cte
			INNER JOIN [condensed].[LadderRungCondensed] lrc ON cte.Pk = lrc.LadderTopId
			)
			SELECT Xref,Pk,[Type] 
			FROM Cte 
			ORDER BY 1,2;
			OPEN csr_deactivate;
			FETCH csr_deactivate INTO @iXref,@iPk,@nvType;
			WHILE @@FETCH_STATUS = 0
			BEGIN
				IF @nvType = 'Ladder'
				BEGIN
					EXECUTE [riskprocessing].[uspLadderTopXrefDeactivateOut] @piLadderTopXrefId=@iXref OUTPUT, @pnvUserName=@pnvUserName;
					EXECUTE [riskprocessing].[uspLadderTopDeactivateOut] @piLadderTopId=@iPk OUTPUT, @pnvUserName=@pnvUserName;
				END
				ELSE IF @nvType = 'Rung'
					EXECUTE [riskprocessing].[uspLadderDBProcessXrefDeactivateOut] @pnvUserName=@pnvUserName,@piLadderDBprocessXrefId=@iXref OUTPUT;
				FETCH csr_deactivate INTO @iXref,@iPk,@nvType;
			END
			SELECT @piRCLadderTopId = RCLadderTopId
			FROM @RCLadderTop;
		END
	END
END
