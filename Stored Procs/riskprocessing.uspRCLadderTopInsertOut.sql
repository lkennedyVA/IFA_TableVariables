USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
   Name: uspRCLadderTopInsertOut
   CreatedBy: Larry Dugger
   Date: 2015-11-12
   Descr: This procedure will insert a new record
   Tables: [riskprocessing].[RCLadderTop]
   
   Functions: [error].[uspLogErrorDetailInsertOut]
   History:
      2015-11-12 - LBD - Created.
*****************************************************************************************/
ALTER PROCEDURE [riskprocessing].[uspRCLadderTopInsertOut](
    @piRCId INT
   ,@piOrgXrefId INT
	,@piLadderTopXrefId INT
	,@pnvCollectionName nvarchar(100)
   ,@piStatusFlag INT
   ,@pnvUserName NVARCHAR(100) = 'N/A' 
   ,@piRCLadderTopId INT OUTPUT
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
   DECLARE @iErrorDetailId INT
      ,@iCurrentTransactionLevel INT
      ,@sSchemaName SYSNAME;
   SET @sSchemaName = N'riskprocessing';
   SET @iCurrentTransactionLevel = @@TRANCOUNT;
   --Will Not update this RCLadderTop to a RCLadderTop already in use
   IF NOT EXISTS(SELECT 'X' 
                  FROM [riskprocessing].[RCLadderTop]
                  WHERE OrgXrefId = @piOrgXrefId
                     AND RCId = @piRCId
							AND LadderTopXrefId = @piLadderTopXrefId)
   BEGIN
      BEGIN TRANSACTION
      BEGIN TRY
         INSERT INTO [riskprocessing].[RCLadderTop]
            OUTPUT inserted.RCLadderTopId
               ,inserted.RCId
               ,inserted.OrgXrefId
					,inserted.LadderTopXrefId
					,inserted.CollectionName
               ,inserted.StatusFlag
               ,inserted.DateActivated
               ,inserted.UserName
            INTO @RCLadderTop
         SELECT @piRCId
				,@piOrgXrefId
				,@piLadderTopXrefId
				,@pnvCollectionName
            ,@piStatusFlag
            ,SYSDATETIME()
            ,@pnvUserName; 
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
         SELECT @piRCLadderTopId = RCLadderTopId
         FROM @RCLadderTop
      END
   END
   ELSE
      SELECT @piRCLadderTopId = -3      
END
