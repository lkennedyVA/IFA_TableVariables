USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: [import].[uspProcessFTBException]
	CreatedBy: Larry Dugger
	Description: This procedure will process all of the unprocessed records

	Tables: [import].[File]
		,[import].[BulkException]

	Procedures: [import].[uspProcessConfirmationRequest]	returns error statuses
		,[import].[uspProcessReverseRequest]				returns error statuses

	History:
		2021-06-03 - LBD - Created
		2021-06-15 - CBS - Added logic to set ClientAccepted = 1 when RuleBreak = 0 
			and ClientAccepted = 2 when RuleBreak = 1
		2025-01-14 - LXK - Replaced table variable with local temp table.
*****************************************************************************************/
ALTER PROCEDURE [import].[uspProcessFTBException](
	 @pnvUserName NVARCHAR(100)
)
AS
BEGIN
	SET NOCOUNT ON;
	drop table if exists #ProcessFTBException
	create table #ProcessFTBException(
		FTBExceptionId bigint
	);
	DECLARE @tblItemConfirmRequest [ifa].[ItemConfirmRequestType];
/* 	drop table if exists #ProcessFTBExceptionItemConfirm
	create table #ProcessFTBExceptionItemConfirm(
	[ItemKey] [nvarchar](25) NULL,
	[ClientItemId] [nvarchar](50) NULL,
	[ClientAccepted] [int] NULL,
	[Fee] [money] NULL,
	[PayoutAmount] [money] NULL
); */
	DECLARE @iOrgId int = 0
		,@iOrgClientId int = 0
		,@bClientVerified bit = 0
		,@biFTBExceptionId bigint
		,@nvProcessKey nvarchar(25)
		,@nvItemKey nvarchar(25)
		,@nvExceptionCode nvarchar(25)
		,@iStatusFlag int = 1
		,@iReverseItemStatusId int = [common].[ufnItemStatus]('Reversed')
		,@iFinalItemStatusId int = [common].[ufnItemStatus]('Final')
		,@iAcceptedClientAcceptedId  int = [common].[ufnClientAccepted]('Accepted')
		,@iDeclinedClientAcceptedId  int = [common].[ufnClientAccepted]('Declined') --2021-06-15
		,@iErrorDetailId int
		,@iCurrentTransactionLevel int
		,@sSchemaName nvarchar(128) = N'import';

	SELECT @iOrgClientId = OrgId
	FROM [organization].[Org] 
	WHERE ExternalCode = 'FTBClnt';

	DECLARE csr_Reverse CURSOR FOR
	SELECT pe.FTBExceptionId,pe.ProcessKey,pe.ItemKey,et.Code, p.OrgId, CONVERT(BIT,CASE WHEN [common].[ufnOrgClientId](p.OrgId) = @iOrgClientId THEN 1 ELSE 0 END) as ClientVerified --0 wrong client
	FROM [import].[FTBException] pe
	INNER JOIN [import].[ExceptionType] et ON pe.ExceptionTypeId = et.ExceptionTypeId
	INNER JOIN [ifa].[Process] p WITH (READUNCOMMITTED) ON pe.ProcessKey = p.ProcessKey
	INNER JOIN [ifa].[Item] i WITH (READUNCOMMITTED) ON p.ProcessId = i.ProcessId
								AND pe.ItemKey = i.ItemKey
	WHERE (et.Code = 'R'		--exception reversals
			OR et.Code = 'C')	--exception confirms --2017-09-05 LBD
		AND Processed = 0		--only those we haven't processed
	ORDER BY pe.FTBExceptionId;
	OPEN csr_Reverse
	FETCH csr_Reverse into @biFTBExceptionId,@nvProcessKey,@nvItemKey,@nvExceptionCode,@iOrgId,@bClientVerified;
	WHILE @@FETCH_STATUS = 0 AND @bClientVerified = 1
	BEGIN
		SET @iStatusFlag = 1;
		IF @nvExceptionCode = 'R'
			EXECUTE [import].[uspProcessReverseRequest] @pnvProcessKey=@nvProcessKey, @pnvItemKey=@nvItemKey, @piOrgId=@iOrgId, @pnvUserName=@pnvUserName, @piStatusFlag=@iStatusFlag OUTPUT;
		ELSE IF @nvExceptionCode = 'C'
		BEGIN
			--GRAB data
			INSERT INTO @tblItemConfirmRequest(ItemKey,ClientItemId,ClientAccepted,Fee,PayoutAmount)
			SELECT ItemKey,ClientItemId,CASE WHEN i.RuleBreak = 0 THEN @iAcceptedClientAcceptedId WHEN i.RuleBreak = 1 THEN @iDeclinedClientAcceptedId END,Fee, Amount --2021-06-15
			--SELECT ItemKey,ClientItemId,@iAcceptedClientAcceptedId,Fee, Amount --2021-06-15
			FROM [ifa].[Process] p WITH (READUNCOMMITTED)
			INNER JOIN [ifa].[Item] i WITH (READUNCOMMITTED) ON p.ProcessId = i.ProcessId
			WHERE p.ProcessKey = @nvProcessKey
				AND i.ItemKey = @nvItemKey;
			IF EXISTS (SELECT 'X' FROM @tblItemConfirmRequest)
				EXECUTE [import].[uspProcessConfirmationRequest] @pnvProcessKey=@nvProcessKey, @piOrgId=@iOrgId, @ptblItemConfirmRequest=@tblItemConfirmRequest, @pnvUserName=@pnvUserName, @piStatusFlag=@iStatusFlag OUTPUT;
			ELSE
				SET @iStatusFlag = [import].[ufnStatusFlag]('DoesntExist');
			DELETE FROM @tblItemConfirmRequest;
		END
		--UPDATE using the StatusFlag received
		UPDATE [import].[FTBException]
			SET Processed = 1
				,StatusFlag = @iStatusFlag
		WHERE FTBExceptionId = @biFTBExceptionId;

		FETCH csr_Reverse into @biFTBExceptionId,@nvProcessKey,@nvItemKey,@nvExceptionCode,@iOrgId,@bClientVerified;
	END
END
